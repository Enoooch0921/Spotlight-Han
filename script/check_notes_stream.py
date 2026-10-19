#!/usr/bin/env python3
"""Exercise the exact Notes stream script with a fake bridge, without accessing Notes."""
import json
import pathlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
source = (root / "Sources/HanSearch/Services/PersonalSources.swift").read_text()
section = source.split("static func notes(", 1)[1].split("static func mail(", 1)[0]
script = re.search(r'let script = #"""(.*?)"""#', section, re.S).group(1)
assert script.count("Application('Notes')") == 1
fixture = r"""
const HanFakeNotes = {notes: function() { return [
    {passwordProtected:()=>false, name:()=>'簡體測試', id:()=>'fixture-1', plaintext:()=>'教会活动\n电脑课程'},
    {passwordProtected:()=>true, name:()=>{throw Error('locked note must not be read');}},
    {passwordProtected:()=>false, name:()=>'容量測試', id:()=>'fixture-2', plaintext:()=>'x'.repeat(100001)},
    {passwordProtected:()=>false, name:()=>{throw Error('unreadable fixture');}}
];}};
"""
script = fixture + script.replace("Application('Notes')", "HanFakeNotes")
result = subprocess.run(["/usr/bin/osascript", "-l", "JavaScript", "-e", script],
                        check=True, capture_output=True, text=True, timeout=10)
events = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
assert events[0] == {"kind": "start", "total": 4, "capped": False}
notes = [event["item"] for event in events if event["kind"] == "note"]
assert len(notes) == 2 and notes[0]["id"] == "fixture-1"
assert "教会活动" in notes[0]["text"] and notes[1]["text"] == ""
assert [event["truncated"] for event in events if event["kind"] == "note"] == [False, True]
assert sum(event["kind"] == "skip" for event in events) == 2
print("PASS: Notes NDJSON streaming, Unicode, locked/unreadable skip and oversized-text limit (fake bridge; no private data).")
