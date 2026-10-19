#!/usr/bin/env python3
"""Exercise the exact resumable Notes script against a fake bridge, never private Notes."""
import json
import pathlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parent.parent
source = (root / 'Sources/HanSearch/Services/NotesReader.swift').read_text()
script = re.search(r'static let script = #"""(.*?)"""#', source, re.S).group(1)
assert script.count("Application('Notes')") == 1
fixture = r"""
const fixtures = {
    'fixture-1':{passwordProtected:()=>false, name:()=>'簡體測試', plaintext:()=>'教会活动\n电脑课程'},
    'locked':{passwordProtected:()=>true, name:()=>{throw Error('locked note must not be read');}, plaintext:()=>{throw Error('locked body must not be read');}},
    'fixture-2':{passwordProtected:()=>false, name:()=>'容量測試', plaintext:()=>'x'.repeat(100001)},
    'unreadable':{passwordProtected:()=>false, name:()=>{throw Error('unreadable fixture');}}
};
const HanFakeNotes = {notes:{id:()=>Object.keys(fixtures), byId:(id)=>fixtures[id]}};
"""
script = fixture + script.replace("Application('Notes')", 'HanFakeNotes')

def run(request):
    result = subprocess.run(['/usr/bin/osascript', '-l', 'JavaScript', '-e', script, json.dumps(request)],
                            check=True, capture_output=True, text=True, timeout=10)
    return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]

manifest = run({'mode':'manifest'})
assert manifest == [{'kind':'manifest', 'ids':['fixture-1', 'locked', 'fixture-2', 'unreadable'], 'capped':False}]
ids = manifest[0]['ids']
first = run({'mode':'read','ids':ids,'budgetMs':0,'textCount':0})
assert [e['id'] for e in first if e['kind']=='note'] == ['fixture-1']
assert first[-1]['kind']=='end'
second = run({'mode':'read','ids':ids[1:],'budgetMs':12000,'textCount':0})
assert [e['id'] for e in second if e['kind']=='begin'] == ids[1:]
assert [e for e in second if e['kind']=='skip'] == [
    {'kind':'skip','id':'locked','protected':True}, {'kind':'skip','id':'unreadable','protected':False}]
notes = [e for e in first + second if e['kind']=='note']
assert len(notes)==2 and '教会活动' in notes[0]['text']
assert notes[1]['text']=='' and notes[1]['truncated']
limited = run({'mode':'read','ids':['fixture-1'],'budgetMs':12000,'textCount':16000000})
assert next(e for e in limited if e['kind']=='note')['truncated']
print('PASS: stable-ID manifest, bounded batch/resume, Unicode, protected/unreadable distinction and text caps (fake bridge; no private data).')
