#!/usr/bin/env python3
"""Exercise the real bundled bridge/XPC/UI path without installing user hooks."""
import argparse, json, pathlib, subprocess, tempfile, time
p = argparse.ArgumentParser()
p.add_argument('--bridge', default='build/IntegrationPackage/debug/notch-agent-bridge')
p.add_argument('--source', choices=['pi','codex','claude','zcode','google-antigravity','all'], default='all')
p.add_argument('--permission', action='store_true')
p.add_argument('--question', action='store_true')
p.add_argument('--cleanup', action='store_true')
p.add_argument('--tasks', action='store_true')
a=p.parse_args(); bridge=str(pathlib.Path(a.bridge).resolve())
sources=['pi','codex','claude','zcode','google-antigravity'] if a.source=='all' else [a.source]
for source in sources:
    sid='notch-smoke-'+source
    path=pathlib.Path(tempfile.gettempdir())/('notch-smoke-'+source+'.jsonl')
    reply='**Integration smoke test**\n\n- Session events arrived through the native bridge.\n- XPC delivered the reply.\n\n```python\nprint("hello notch")\n```'
    if not a.cleanup:
        path.write_text(json.dumps({'type':'assistant','message':{'role':'assistant','content':[{'type':'text','text':reply}]}},ensure_ascii=False)+'\n')
    base={'session_id':sid,'_source':source,'cwd':str(pathlib.Path.cwd()),'transcript_path':str(path)}
    def send(event, **extra):
        payload=base|{'hook_event_name':event}|extra
        args=[bridge,'--source',source,'--event',event]
        return subprocess.run(args,input=json.dumps(payload),text=True,capture_output=True,timeout=120)
    if a.cleanup:
        send('SessionEnd'); path.unlink(missing_ok=True); print(source, 'removed'); continue
    for event in ['SessionStart','UserPromptSubmit','PreToolUse','PostToolUse']:
        result=send(event,prompt='Synthetic integration smoke test',tool_name='Read',tool_input={'file_path':'README.md'},tool_response={'success':True})
        if result.returncode: raise SystemExit(result.stderr)
    if a.tasks:
        task_input={'todos':[{'content':'Verify bridge','status':'completed','activeForm':'Verifying bridge'},{'content':'Review notch','status':'in_progress','activeForm':'Reviewing notch'}]}
        send('PreToolUse',tool_name='TodoWrite',tool_input=task_input,tool_use_id='fixture-task-list')
        send('PostToolUse',tool_name='TodoWrite',tool_input=task_input,tool_use_id='fixture-task-list',tool_response={'success':True})
    if a.question:
        result=send('PermissionRequest', tool_name='AskUserQuestion', tool_input={'questions':[{'question':'Smoke test: select a response','header':'Test','options':[{'label':'A','description':'First fixture'},{'label':'B','description':'Second fixture'}],'multiSelect':False}]})
        response=json.loads(result.stdout or '{}'); print(source,'question response:',json.dumps(response));
    elif a.permission and source!='google-antigravity':
        result=send('PermissionRequest',tool_name='Bash',tool_input={'command':'printf "synthetic smoke test"','description':'Synthetic UI approval check; no command will execute.'})
        response=json.loads(result.stdout or '{}');print(source,'permission response:',json.dumps(response))
    send('Stop',last_assistant_message=reply)
    print(source,'lifecycle delivered')
