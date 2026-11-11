#!/usr/bin/env python3
"""Live integration test with two disposable Supabase anonymous identities.

Usage (do NOT paste tokens/keys in chat or commit them):
  SUPABASE_URL=https://PROJECT.supabase.co SUPABASE_PUBLISHABLE_KEY=... python tools/live_supabase_rls_test.py
Run only on a TEST Supabase project with anonymous sign-ins enabled and
supabase/01_leaderboard.sql installed. Uses synthetic ranking scores only.
"""
import os, json, sys, urllib.request, urllib.error, uuid
base=os.getenv('SUPABASE_URL','').rstrip('/')
key=os.getenv('SUPABASE_PUBLISHABLE_KEY','')
if not base.startswith('https://') or len(key)<20:
    sys.exit('BLOCKED: set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY for your TEST project')

def request(method,path,token=None,payload=None,extra=None):
    headers={'apikey':key,'Content-Type':'application/json'}
    if token is not None: headers['Authorization']='Bearer '+token
    if extra: headers.update(extra)
    data=None if payload is None else json.dumps(payload).encode()
    req=urllib.request.Request(base+path, data=data, headers=headers,method=method)
    try:
        with urllib.request.urlopen(req,timeout=25) as r:
            buf=r.read().decode()
            return r.status, json.loads(buf) if buf else None
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode(errors='replace') or '{}')

def anonymous():
    code,data=request('POST','/auth/v1/signup',payload={'data':{}})
    if code not in (200,201) or not isinstance(data,dict) or not data.get('access_token') or not data.get('user',{}).get('id'):
        raise RuntimeError('Anonymous login failed: HTTP '+str(code)+'; enable Supabase Anonymous Sign-ins')
    return data['access_token'],data['user']['id']

def check(condition,comment):
    print(('PASS' if condition else 'FAIL')+': '+comment)
    if not condition: raise AssertionError(comment)

print('RLS integration test: creates disposable auth users and synthetic records')
a_token,a_id=anonymous()
b_token,b_id=anonymous()
headers={'Prefer':'return=representation'}
path='/rest/v1/oranaplo_rankings'
row={'user_id':a_id,'display_name':'QA'+uuid.uuid4().hex[:8], 'total_steps':2500,'longest_run_m':1000,'published':True}
try:
    status,created=request('POST',path,a_token,[row],headers)
    check(status in (200,201) and isinstance(created,list) and len(created)==1,'A inserts own ranking')
    status,public=request('GET',path+'?select=user_id&published=eq.true&user_id=eq.'+a_id,b_token)
    check(status==200 and len(public)==1,'B sees A published ranking')
    status,updated=request('PATCH',path+'?user_id=eq.'+a_id,a_token,{'published':False},headers)
    check(status==200 and len(updated)==1,'A hides own ranking')
    status,private=request('GET',path+'?select=user_id&user_id=eq.'+a_id,b_token)
    check(status==200 and private==[],'B cannot see hidden ranking')
    status,forged=request('PATCH',path+'?user_id=eq.'+a_id,b_token,{'total_steps':999999},headers)
    check(status==200 and forged==[],'B cannot update A ranking')
    status,forged=request('DELETE',path+'?user_id=eq.'+a_id,b_token,extra=headers)
    check(status==200 and forged==[],'B cannot delete A ranking')
    status,forged=request('POST',path,b_token,[{'user_id':a_id,'display_name':'BadActor','total_steps':999,'longest_run_m':0,'published':True}],headers)
    check(status in (400,401,403,409),'B cannot insert as A')
    status,own=request('GET',path+'?select=user_id,total_steps&user_id=eq.'+a_id,a_token)
    check(status==200 and len(own)==1 and own[0]['total_steps']==2500,'A record remains unchanged')
    status,guest=request('GET',path+'?select=user_id&user_id=eq.'+a_id)
    check(status in (401,403) or (status==200 and guest==[]),'Guest cannot access private data')
    print('RESULT: PASS (synthetic RLS requests). This does NOT validate every other service.')
finally:
    code,data=request('DELETE',path+'?user_id=eq.'+a_id,a_token,extra=headers)
    print('Cleanup synthetic ranking A:',code)
