#!/usr/bin/env python3
"""Scoped session stop/start around the checksum-guarded installer."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

PACKAGE=Path(__file__).resolve().parent

def process_info(pid):
    proc=Path('/proc')/str(pid)
    try:
        if proc.stat().st_uid!=os.getuid():return None
        stat=(proc/'stat').read_text().rsplit(')',1)[1].split()
        if stat[0]=='Z':return None
        args=[x.decode(errors='replace') for x in (proc/'cmdline').read_bytes().split(b'\0') if x]
        env={}
        for raw in (proc/'environ').read_bytes().split(b'\0'):
            key,sep,value=raw.partition(b'=')
            if sep and key in (b'SERPANTINUM_DIR',b'MAIN_QML'):
                env[key.decode()]=value.decode(errors='replace')
        return {'pid':int(pid),'args':args,'env':env,'started':stat[19]}
    except (OSError,ValueError,IndexError):return None

def is_target(info,runtime):
    if not info or not info['args']:return False
    args=info['args'];runtime=runtime.resolve();shell=runtime/'quickshell/Shell.qml'
    daemon=any(Path(a).name=='serpantinumd' for a in args[:2])
    qs=Path(args[0]).name in ('quickshell','qs')
    if not (daemon or qs):return False
    if daemon and any(a in ('stop', 'status', '--help', '-h', '--version', '-V') for a in args[2:]):return False
    if qs:
        for i,arg in enumerate(args[:-1]):
            if arg in ('-p','--path') and Path(args[i+1]).resolve()==shell:return True
        return any(a.startswith('--path=') and Path(a[7:]).resolve()==shell for a in args)
    env=info['env']
    if env.get('SERPANTINUM_DIR'):return Path(env['SERPANTINUM_DIR']).resolve()==runtime
    if env.get('MAIN_QML'):return Path(env['MAIN_QML']).resolve()==shell
    return any(Path(a).resolve()==runtime.parent/'bin/serpantinumd' for a in args[:2])

def target_processes(runtime):
    result=[]
    for proc in Path('/proc').glob('[0-9]*'):
        info=process_info(proc.name)
        if is_target(info,runtime):result.append(info)
    return result

def same_pid_namespace():
    return os.readlink('/proc/self') == str(os.getpid())

def stop_target(runtime):
    if not same_pid_namespace():
        raise RuntimeError('Automatic restart requires /proc and the installer to share a PID namespace. Use a normal Hyprland terminal, or stop the session manually and install without --restart.')
    # No pkill, no pattern-based termination, no global daemon stop command.
    seen=set()
    deadline=time.monotonic()+7
    while time.monotonic()<deadline:
        targets=target_processes(runtime)
        if not targets:return
        for info in targets:
            key=(info['pid'],info['started'])
            if key in seen:continue
            current=process_info(info['pid'])
            if current and current['started']==info['started'] and is_target(current,runtime):
                try:os.kill(info['pid'],signal.SIGTERM)
                except ProcessLookupError:pass
                seen.add(key)
        time.sleep(0.1)
    raise RuntimeError('Target session did not stop within 7 seconds. No installation performed; close its terminal or stop its supervisor first.')

if __name__ == '__main__':
    try:
        stop_target(Path(__file__).resolve().parent.parent)
    except (RuntimeError, OSError) as exc:
        sys.exit('ERROR: ' + str(exc))
