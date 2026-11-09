import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {parseTaskRecord} from '../runtime/task-state.mjs';
import {CompletionMonitor,CompletionRolloutTail} from '../runtime/completion-monitor.mjs';

test('task-state CLI flag without a checkpoint path cannot create a flag-named state file',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'task-pet-cli-'));
  try{
    const script=fileURLToPath(new URL('../runtime/completion-monitor.mjs',import.meta.url));
    const child=spawnSync(process.execPath,[script,'--task-states'],{cwd:dir,env:{...process.env,CODEX_HOME:dir},input:'',encoding:'utf8',timeout:5000});
    assert.equal(child.status,0,child.stderr);
    assert.equal(fs.existsSync(path.join(dir,'--task-states')),false);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test('task lifecycle and tool metadata become states without disclosing transcript',()=>{
  const context={},options={context,sessionId:'session'};
  const record=(type,payload)=>({type,timestamp:new Date().toISOString(),payload});
  const event=p=>parseTaskRecord(record('event_msg',p),options);
  assert.equal(event({type:'task_started',turn_id:'one'}).state,'thinking');
  const tool=parseTaskRecord(record('response_item',{type:'function_call',name:'apply_patch',arguments:'private code'}),options);
  assert.equal(tool.state,'coding');assert.ok(!JSON.stringify(tool).includes('private'));
  assert.equal(parseTaskRecord(record('response_item',{type:'function_call',name:'web_search'}),options).state,'searching');
  assert.equal(parseTaskRecord(record('response_item',{type:'function_call',name:'request_user_input'}),options).state,'waiting');
  assert.equal(event({type:'task_complete',turn_id:'one',last_agent_message:'private answer'}).state,'completed');
  assert.equal(parseTaskRecord(record('response_item',{type:'reasoning'}),options),null);
  assert.equal(event({type:'task_started',turn_id:'two'}).state,'thinking');
  assert.equal(event({type:'turn_aborted',turn_id:'two'}).state,'interrupted');
  assert.equal(event({type:'task_complete',turn_id:'three',status:'failed'}).state,'error');
  assert.equal(parseTaskRecord({...record('event_msg',{type:'task_started',turn_id:'old'}),timestamp:'2020-01-01'}, {...options,since:Date.now()}),null);
  event({type:'task_started',turn_id:'nested'});
  assert.equal(parseTaskRecord(record('response_item',{type:'custom_tool_call',name:'functions.exec',input:'await tools.apply_patch("private patch")'}),options).state,'coding');
});

test('same-state activity keeps a long-running task fresh and input resumes only on its matching reply',()=>{
  const context={},start=Date.now(),options={context,sessionId:'session',since:start};
  const parse=(type,payload,ms)=>parseTaskRecord({type,payload,timestamp:start+ms},options);
  assert.equal(parse('event_msg',{type:'task_started',turn_id:'long'},-1000),null);
  assert.equal(parse('response_item',{type:'function_call',name:'exec_command'},0).state,'working');
  assert.equal(parse('response_item',{type:'function_call',name:'exec_command'},180000).at,start+180000);
  assert.equal(parse('response_item',{type:'function_call',name:'request_user_input',call_id:'input'},180001).state,'waiting');
  assert.equal(parse('response_item',{type:'function_call_output',call_id:'other',output:'private output'},180002),null);
  assert.equal(parse('response_item',{type:'reasoning'},180003).state,'waiting');
  assert.equal(parse('response_item',{type:'function_call_output',call_id:'input',output:'private answer'},180004).state,'thinking');
  assert.equal(parse('event_msg',{type:'task_complete',turn_id:'older'},180005),null);
  assert.equal(context.active,true);
  assert.equal(parse('event_msg',{type:'task_complete',turn_id:'long'},180006).state,'completed');
  assert.equal(parse('event_msg',{type:'turn_complete',turn_id:'long'},180007),null);
  assert.equal(parse('event_msg',{type:'task_started',turn_id:'stale'},-2000),null);
  assert.equal(context.turnId,'long');
});

test('task callback failure cannot swallow a completion and a rewritten log clears old task context',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'task-pet-')),file=path.join(dir,'rollout.jsonl');
  const line=(type,payload)=>JSON.stringify({type,timestamp:new Date().toISOString(),payload})+'\n';
  try{
    fs.writeFileSync(file,line('event_msg',{type:'task_started',turn_id:'one'}));
    const tail=new CompletionRolloutTail(file,{onActivity:()=>{throw new Error('callback failure');}});
    tail.update();
    fs.appendFileSync(file,line('event_msg',{type:'task_complete',turn_id:'one'}));
    assert.equal(tail.update()[0].turnId,'one');
    fs.writeFileSync(file,line('response_item',{type:'function_call',name:'exec_command'}));
    tail.update();assert.equal(tail.taskContext.active,undefined);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});

test('archive checkpoint preserves the running task without retaining tool input',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'task-pet-')),folder=path.join(dir,'sessions');
  fs.mkdirSync(folder);const file=path.join(folder,'rollout.jsonl'),events=[];
  const line=(type,payload)=>JSON.stringify({type,timestamp:new Date().toISOString(),payload})+'\n';
  const monitor=new CompletionMonitor({codexHome:dir,since:0,onActivity:e=>events.push(e)});
  try{
    fs.writeFileSync(file,line('session_meta',{source:'vscode'})+line('event_msg',{type:'task_started',turn_id:'one'}));
    monitor.scan();const tail=[...monitor.tails.values()][0];
    monitor.rememberCheckpoint(path.basename(file),tail);monitor.tails.clear();
    assert.ok(!JSON.stringify([...monitor.checkpoints.values()]).includes('private'));
    fs.appendFileSync(file,line('response_item',{type:'function_call',name:'apply_patch',arguments:'private code'}));
    monitor.scan();assert.equal(events.at(-1).state,'coding');
  }finally{monitor.stop();fs.rmSync(dir,{recursive:true,force:true});}
});

test('baseline seeds an active turn, partial JSONL is buffered, old completions stay silent',()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'task-pet-')),file=path.join(dir,'rollout.jsonl');
  const line=p=>JSON.stringify({type:'event_msg',timestamp:new Date().toISOString(),payload:p})+'\n';
  try{
    fs.writeFileSync(file,line({type:'task_started',turn_id:'one'}));
    const events=[],tail=new CompletionRolloutTail(file,{baseline:true,onActivity:e=>events.push(e)});
    assert.equal(events.at(-1).state,'thinking');
    const done=line({type:'task_complete',turn_id:'one'});
    fs.appendFileSync(file,done.slice(0,-1));tail.update();assert.equal(events.length,1);
    fs.appendFileSync(file,'\n');tail.update();assert.equal(events.at(-1).state,'completed');
    const replay=[];new CompletionRolloutTail(file,{baseline:true,onActivity:e=>replay.push(e)});assert.equal(replay.length,0);
  }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
