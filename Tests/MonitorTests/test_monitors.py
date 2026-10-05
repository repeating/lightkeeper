"""Exercise the actual adapters against an isolated IPC server and registry."""
import json
import os
from pathlib import Path
import select
import socket
import sqlite3
import struct
import subprocess
import sys
import tempfile
import time

with tempfile.TemporaryDirectory(prefix="beacon-monitor-") as temporary:
    home = Path(temporary)
    ipc = home / ".codex/ipc"
    ipc.mkdir(parents=True)
    database = home / ".codex/state_5.sqlite"
    connection = sqlite3.connect(database)
    connection.executescript("""
      CREATE TABLE threads (id TEXT,title TEXT,cwd TEXT,archived INTEGER,agent_path TEXT,thread_source TEXT,originator TEXT,recency_at INTEGER);
      INSERT INTO threads VALUES ('fixture','Fixture task','/Projects/Test',0,'/root','user','Codex Desktop',strftime('%s','now'));
    """)
    connection.close()
    registry = home / ".claude/sessions"
    registry.mkdir(parents=True)
    claude = registry / f"{os.getpid()}.json"

    def write_claude(status):
        temporary_file = claude.with_suffix(".tmp")
        temporary_file.write_text(json.dumps({"pid": os.getpid(), "sessionId": "fixture-claude", "name": "Claude fixture", "status": status, "waitingFor": "input needed"}))
        temporary_file.replace(claude)

    write_claude("busy")
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(str(ipc / "ipc.sock"))
    listener.listen(1)
    listener.settimeout(4)
    process = subprocess.Popen([sys.argv[1]], env={**os.environ, "BEACON_TEST_HOME": str(home)}, stdout=subprocess.PIPE, text=True)
    peer, _ = listener.accept()
    peer.setblocking(False)
    buffer = b""
    events = []
    methods = []
    started = time.monotonic()
    revision = 0
    owner = "owner-a"
    state = "active"
    flags = []
    items = []
    switches = set()
    saved_database = database.with_suffix(".saved")
    recovered_follow = False
    has_metadata_error = False

    def send(message):
        body = json.dumps(message).encode()
        peer.sendall(struct.pack("<I", len(body)) + body)

    def broadcast(method, params, source=None):
        send({"type": "broadcast", "method": method, "version": 1, "sourceClientId": source or owner, "params": params})

    def snapshot():
        global revision
        revision += 1
        broadcast("thread-stream-state-changed", {"hostId": "local", "conversationId": "fixture", "change": {
            "type": "snapshot", "revision": revision, "conversationState": {
                "title": "Fixture task", "threadRuntimeStatus": {"type": state, "activeFlags": flags}, "requests": [], "turns": [{"status":"inProgress", "items":items}]
            }}})

    try:
        while process.poll() is None:
            elapsed = time.monotonic() - started
            if elapsed > 1 and "disconnect" not in switches:
                switches.add("disconnect")
                broadcast("client-status-changed", {"clientId": "owner-a", "status": "disconnected"}, "owner-a")
            if elapsed > 2 and "new-owner" not in switches:
                switches.add("new-owner")
                owner = "owner-b"
                flags = ["waitingOnUserInput"]
                broadcast("thread-stream-following-status-requested", {"hostId": "local", "conversationId": "fixture"})
                write_claude("waiting")
            if elapsed > 3.5 and "metadata-failure" not in switches:
                switches.add("metadata-failure")
                database.replace(saved_database)
                write_claude("idle")
            if elapsed > 11 and "async-question" not in switches:
                switches.add("async-question")
                flags = []
                items = [{"type":"agentMessage", "id":"async-question", "questions":[{"title":"Desktop or browser?"}]}]
                snapshot()
            if elapsed > 13 and "async-answer" not in switches:
                switches.add("async-answer")
                answer = [{"questionItemId":json.dumps(["request_user_input_async", "async-question", 0],separators=(",",":")), "answer":"Both"}]
                items.append({"type":"steeringUserMessage", "status":"accepted", "input":[{"type":"text", "text":"<send_user_message_question_reply>"+json.dumps(answer)+"</send_user_message_question_reply>"}]})
                snapshot()
            readable, _, _ = select.select([peer, process.stdout], [], [], 0.1)
            for stream in readable:
                if stream is peer:
                    chunk = peer.recv(65536)
                    if not chunk:
                        continue
                    buffer += chunk
                    while len(buffer) >= 4:
                        size = struct.unpack("<I", buffer[:4])[0]
                        if len(buffer) < size + 4:
                            break
                        message = json.loads(buffer[4:4 + size])
                        buffer = buffer[4 + size:]
                        methods.append(message.get("method"))
                        if message.get("method") == "initialize":
                            send({"type": "response", "method": "initialize", "requestId": message["requestId"], "resultType": "success", "result": {"clientId": "probe"}})
                        elif message.get("method") == "thread-stream-following-changed":
                            if has_metadata_error and database.exists():
                                recovered_follow = True
                            snapshot()
                else:
                    line = stream.readline()
                    if line:
                        event = json.loads(line)
                        event["elapsed"] = elapsed
                        events.append(event)
                        if event.get("connected") is False and "metadata unavailable" in event.get("detail", ""):
                            has_metadata_error = True
                            if saved_database.exists():
                                saved_database.replace(database)
        events.extend(json.loads(line) for line in process.stdout.read().splitlines() if line)
    finally:
        process.wait(timeout=3)
        peer.close()
        listener.close()

    checks = {
        "owner disconnect marks session unavailable": any(e.get("source") == "Codex" and e.get("state") == "unknown" for e in events),
        "new owner follower request refreshes state": any(e.get("source") == "Codex" and e.get("state") == "needsInput" for e in events),
        "temporary metadata failure observed": has_metadata_error,
        "metadata recovery requests fresh snapshot": recovered_follow,
        "metadata recovery restores connection": has_metadata_error and any(e.get("connected") is True for e in events[ next((i for i,e in enumerate(events) if e.get("connected") is False), len(events)) + 1:]),
        "Claude running waiting and idle transitions": {e.get("state") for e in events if e.get("source") == "Claude"} >= {"running", "needsInput", "finished"},
        "async question is orange while runtime remains active": any(e.get("source")=="Codex" and e.get("state")=="needsInput" and 11 <= e.get("elapsed",0) < 13 for e in events),
        "accepted async answer restores running": any(e.get("source")=="Codex" and e.get("state")=="running" and e.get("elapsed",0) >= 13 for e in events),
        "monitor never starts or controls turns": set(methods) <= {"initialize", "thread-stream-following-changed"},
    }
    for name, passed in checks.items():
        print(("PASS " if passed else "FAIL ") + name)
    sys.exit(0 if all(checks.values()) else 1)
