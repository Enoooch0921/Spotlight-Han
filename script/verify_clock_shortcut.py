#!/usr/bin/env python3
"""Verify the distributable shortcut matches its reviewable source; never run Clock."""
import pathlib
import plistlib
import struct
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = plistlib.loads((root / 'Assets/Shortcuts/SystemClock.plist').read_bytes())
signed = root / 'Assets/Shortcuts/Spotlight-Han-System-Clock.shortcut'
data = signed.read_bytes()
assert data[:4] == b'AEA1', 'Expected an Apple-signed shortcut archive'
length = struct.unpack('<I', data[8:12])[0]
metadata = plistlib.loads(data[12:12 + length])
with tempfile.TemporaryDirectory() as directory:
    scratch = pathlib.Path(directory)
    certificate = scratch / 'certificate.der'
    certificate.write_bytes(metadata['SigningCertificateChain'][0])
    public_key = subprocess.run(['/usr/bin/openssl', 'x509', '-inform', 'DER', '-in', str(certificate), '-pubkey', '-noout'], check=True, capture_output=True).stdout
    key = scratch / 'public.pem'
    key.write_bytes(public_key)
    archive = scratch / 'shortcut.aar'
    subprocess.run(['/usr/bin/aea', 'decrypt', '-i', str(signed), '-o', str(archive), '-sign-pub', str(key)], check=True, capture_output=True)
    subprocess.run(['/usr/bin/aa', 'extract', '-i', str(archive), '-d', str(scratch)], check=True, capture_output=True)
    actual = plistlib.loads((scratch / 'Shortcut.wflow').read_bytes())
    assert actual == source, 'Signed shortcut differs from SystemClock.plist; sign the updated source again'
assert [a['WFWorkflowActionIdentifier'] for a in source['WFWorkflowActions']] == [
    'is.workflow.actions.detect.dictionary',
    'is.workflow.actions.getvalueforkey',
    'is.workflow.actions.getvalueforkey',
    'com.apple.mobiletimer-framework.MobileTimerIntents.MTCreateAlarmIntent',
    'is.workflow.actions.gettext',
], 'Unexpected companion actions'
assert source['WFWorkflowActions'][-1]['WFWorkflowActionParameters']['WFTextActionText'] == 'SPOTLIGHT_HAN_CLOCK_CREATED_V1'
print('PASS: signed Clock companion matches its source; no alarm created')
