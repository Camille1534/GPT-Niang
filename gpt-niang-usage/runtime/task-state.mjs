// Local rollout metadata only. Prompts, tool output and credentials never leave this process.
export function parseTaskRecord(record, {sessionId='', since=0, context={}}={}) {
  const p=record?.payload;
  if(!p || !['event_msg','response_item','turn_context'].includes(record.type))return null;
  const at=typeof record.timestamp==='number'?record.timestamp:Date.parse(record.timestamp);
  if(!Number.isFinite(at))return null;
  if(context.at>at)return null;
  const previousTurn=context.turnId,previousState=context.state;
  const terminal=record.type==='event_msg' && ['task_complete','turn_complete','turn_aborted','task_aborted','error','task_failed','turn_failed'].includes(p.type);
  if(terminal && context.active && p.turn_id && p.turn_id!==context.turnId)return null;
  if(typeof p.turn_id==='string' && p.turn_id.length<=256)context.turnId=p.turn_id;
  if(record.type==='turn_context')context.active=true;
  let state;
  if(record.type==='event_msg') {
    if(['task_started','turn_started'].includes(p.type)){state='thinking';context.active=true;context.waitingCallId=null;}
    else if(['task_complete','turn_complete'].includes(p.type)){
      state=p.error || ['failed','error','errored'].includes(p.status)?'error': /cancel|abort|interrupt/.test(p.status||'')?'interrupted':'completed';context.active=false;
    } else if(['turn_aborted','task_aborted'].includes(p.type)){state='interrupted';context.active=false;}
    else if(['error','task_failed','turn_failed'].includes(p.type)){state='error';context.active=false;}
    else if(['request_user_input','approval_requested'].includes(p.type))state='waiting';
    else if(p.type==='agent_reasoning' && context.active)state='thinking';
  } else if(record.type==='response_item' && context.active) {
    if(['function_call','custom_tool_call'].includes(p.type)) {
      // Inspect only tool metadata to distinguish actions. Never emit the arguments.
      let name=String(p.name||'');
      if(/(^|\.)exec$/.test(name)){
        const input=String(p.input||p.arguments||'').slice(0,65536);
        const nested=input.match(/\btools\.(apply_patch|web__run|request_user_input\w*)\s*\(/);
        if(nested)name=nested[1];
      }
      if(/request_user_input/.test(name)){
        const id=p.call_id??p.id;
        if(typeof id==='string' && id.length<=256)context.waitingCallId=id;
        state='waiting';
      }else state=context.waitingCallId?'waiting':/search|browse|web/.test(name)?'searching':/apply_patch|edit|write_file/.test(name)?'coding':'working';
    } else if(['function_call_output','custom_tool_call_output'].includes(p.type)){
      if(context.waitingCallId && p.call_id!==context.waitingCallId)return null;
      context.waitingCallId=null;state='thinking';
    } else if(p.type==='reasoning')state=context.waitingCallId?'waiting':'thinking';
  }
  if(!state || typeof context.turnId!=='string' || !context.turnId || context.turnId.length>256)return null;
  if(terminal)context.waitingCallId=null;
  context.state=state;context.at=at;
  // Recovery reads old lifecycle records to seed context, without replaying speech.
  if(at<since)return null;
  // Ongoing activity refreshes the UI's timeout even when its label is unchanged.
  if(terminal && previousTurn===context.turnId && previousState===state)return null;
  return {type:'task-state',sessionId,turnId:context.turnId,state,at};
}
