'use strict';
const assert=require('node:assert/strict');
module.exports=async(db,{actor,A,B,C,TAB})=>{
  await actor(A);
  const query=async(sql,args=[])=>(await db.query(sql,args)).rows[0].data;
  const balance=await query('SELECT public.get_tab_balances_v1($1) data',[[TAB]]);
  assert.equal(balance.account_id,A);
  const legacy=(await db.query('SELECT public.get_net_balance($1,$2) n',[TAB,A])).rows[0].n;
  assert.equal(String(balance.balances[0].net_balance_centavos),String(legacy));
  await db.exec('RESET ROLE');
  const expected=(await db.query('SELECT id FROM public.transactions WHERE tab_id=$1 ORDER BY id',[TAB])).rows.map(r=>r.id);
  await actor(A);
  const seen=[];let cursor=null;
  do {
    const page=await query('SELECT public.get_tab_ledger_page_v1($1,$2,$3,$4) data',[[TAB],'transactions',cursor,2]);
    assert.equal(page.account_id,A);assert.equal(page.kind,'transactions');
    assert.ok(page.records.length<=2);
    for(const r of page.records){assert.equal(r.tab_id,TAB);assert.ok(Array.isArray(r.transaction_participants));seen.push(r.id);}
    cursor=page.next_cursor;
  } while(cursor);
  assert.deepEqual(seen,expected);
  await assert.rejects(query('SELECT public.get_tab_ledger_page_v1($1,$2,NULL,201) data',[[TAB],'transactions']),e=>e.code==='22023');
  await actor(C);
  await assert.rejects(query('SELECT public.get_tab_balances_v1($1) data',[[TAB]]),e=>e.code==='42501');
  await assert.rejects(query('SELECT public.get_tab_ledger_page_v1($1,$2) data',[[TAB],'payments']),e=>e.code==='42501');
  await db.exec('RESET ROLE');
  // Isolated synthetic scale fixture; no effect on other contract accounts.
  const owner='90000000-0000-4000-8000-000000000001';
  await db.query('INSERT INTO public.users(id,display_name) VALUES($1,$2)',[owner,'Synthetic scale fixture']);
  await db.exec(`INSERT INTO public.users(id,display_name)
    SELECT ('93000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Synthetic peer' FROM generate_series(1,100) i`);
  await db.query(`INSERT INTO public.tabs(id,user_a,user_b)
    SELECT ('91000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,$1,
      ('93000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(1,100) i`,[owner]);
  await db.query(`INSERT INTO public.transactions(id,tab_id,created_by,description,total_amount_centavos)
    SELECT ('92000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
      ('91000000-0000-4000-8000-'||lpad(((i-1)/100+1)::text,12,'0'))::uuid,$1,'Synthetic scale entry',100
    FROM generate_series(1,10000) i`,[owner]);
  await actor(owner);
  const ids=Array.from({length:100},(_,i)=>'91000000-0000-4000-8000-'+String(i+1).padStart(12,'0'));
  const start=Date.now();cursor=null;let count=0,pages=0;
  do{const page=await query('SELECT public.get_tab_ledger_page_v1($1,$2,$3,200) data',[ids,'transactions',cursor]);
    count+=page.records.length;pages++;cursor=page.next_cursor;
  }while(cursor);
  assert.equal(count,10000);assert.equal(pages,50);
  assert.equal((await query('SELECT public.get_tab_balances_v1($1) data',[ids])).balances.length,100);
  console.log(`LEDGER_PAGES_OK: 100 tabs / 10000 records, 50 bounded pages, one balance batch; ${Date.now()-start}ms local synthetic read. Role denial and balance parity passed; not device/live Supabase evidence.`);
};
