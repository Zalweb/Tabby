export function makeHandler({serviceKey,secret,rpc}){
  return async request=>{
    if(request.method!=='POST')return new Response(null,{status:405});
    if(!serviceKey||!secret)return new Response('Worker unavailable',{status:503});
    if(request.headers.get('authorization')!==`Bearer ${serviceKey}`||request.headers.get('x-recurrence-secret')!==secret)return new Response(null,{status:403});
    try{
      const result=await rpc('materialize_due_recurrences_v1',{p_limit:25});
      if(!result||!Number.isInteger(result.processed)||!Number.isInteger(result.needs_attention)||
        result.processed<0||result.needs_attention<0||result.processed+result.needs_attention>25)throw Error('Invalid acknowledgement');
      return Response.json({processed:result.processed,needs_attention:result.needs_attention});
    }catch(_){return new Response('Batch not acknowledged. Retry safely.',{status:503});}
  };
}
