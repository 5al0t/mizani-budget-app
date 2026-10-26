const { test } = require('node:test');
const assert = require('node:assert/strict');
const core = require('../Mizani/Resources/core.js');
const now = '2026-10-26T12:00:00.000Z';
const account = '0000XXXXXXXX0017';
// Synthetic identities and IDs; these retain the formats and amounts supplied by the user.
const messages = [
  `Dear Customer, You have sent OMR 80.000 to TEST PERSON A from your a/c ${account} on 25/10/2026 12:00:05 using Mobile Payment services. Txn Id TEST000001. Avl Bal OMR 49.699.`,
  `Dear Customer, You have sent OMR 200.000 to TEST PERSON B from your a/c ${account} on 23/10/2026 21:01:56 using Mobile Payment services. Txn Id TEST000002. Avl Bal OMR 131.599.`,
  `Dear customer, your transaction on card for OMR 0.625 has been reversed and credited to ${account} on 18/10/2026 21:16:15. New Available Balance is OMR 138.879.`,
  `Dear Customer, You have sent OMR 2.000 to TEST PERSON C from your a/c ${account} on 13/10/2026 18:49:44 using Mobile Payment services. Txn Id TEST000004. Avl Bal OMR 150.454.`,
  `عزيزي الزبون، لقد استلمت OMR 26.000 من TEST PERSON D في حسابك ${account} باستخدام خدمات الدفع عبر الهاتف النقال/ المحفظة الإلكترونية. . رقم المعاملةTEST000005. رصيدك الحالي هو OMR 155.079.`,
  `تم خصم 5.000 OMR من حسابك رقم ${account} بإستخدام بطاقة الخصم المباشر في 841861-ROP TRAFFIC SERVICES MUSC بتاريخ 2026/10/11 07:42:34. رصيدك الحالي هو 1.079 OMR.`,
  `تم إيداع 30.000 OMR في حسابك رقم ${account} عن طريق جهاز الإيداع النقدي التابع لبنك مسقط بتاريخ 2026/10/11 08:19:38. رصيدك الحالي هو 31.079 OMR.`
];
const act = (action, payload = {}, state = undefined, date = now) => core.perform({ action, payload, state, now: date });
const imported = () => act('import', { text: messages.join('\n\n') });
const anchor = () => act('anchor', { account, amount: '100.000' });

test('all seven supplied message formats parse into five operation types', () => {
  const p = core.parse(messages.join('\n\n'), now);
  assert.equal(p.errors.length, 0);
  assert.deepEqual(p.transactions.map(t => t.kind), ['outgoing', 'outgoing', 'refund', 'outgoing', 'incoming', 'purchase', 'deposit']);
  assert.deepEqual(p.transactions.map(t => t.amount), [80000, 200000, 625, 2000, 26000, 5000, 30000]);
  assert.equal(p.transactions[5].category, 'خدمات حكومية');
});
test('latest dated bank balance is 49.699, not a sum of incomplete history', () => {
  const r = imported(); assert.equal(r.snapshot.accounts[0].balance, 49699);
  assert.ok(r.snapshot.alerts.some(a => a.id.startsWith('gap-')));
});
test('out-of-order SMS never overwrites a newer bank balance', () => {
  let r = act('import', { text: messages[0] }); r = act('import', { text: messages[6] }, r.state);
  assert.equal(r.snapshot.accounts[0].balance, 49699);
});
test('reimport is idempotent and does not retain raw message text', () => {
  const a = imported(), b = act('import', { text: messages.join('\n\n') }, a.state);
  assert.equal(b.result.added, 0); assert.equal(b.result.duplicates, 7); assert.equal(b.state.transactions.length, 7);
  assert.ok(!JSON.stringify(b.state).includes('Dear Customer'));
});
test('different bank IDs are not merged merely because all other fields match', () => {
  const r = act('import', { text: messages[0] + '\n\n' + messages[0].replace('TEST000001', 'TEST000099') });
  assert.equal(r.result.added, 2);
});
test('missing date is explicit, excluded from balance anchors and month reports', () => {
  const r = act('import', { text: messages[4] });
  assert.equal(r.snapshot.accounts[0].balance, null); assert.equal(r.snapshot.pending, 1); assert.equal(r.snapshot.income, 0);
});
test('reviewing missing date promotes its bank balance at the confirmed date', () => {
  let r = act('import', { text: messages[4] });
  r = act('editTransaction', { id: r.state.transactions[0].id, date: '2026-10-12T12:00:00Z' }, r.state);
  assert.equal(r.snapshot.pending, 0); assert.equal(r.snapshot.accounts[0].balance, 155079); assert.equal(r.snapshot.income, 26000);
});
test('dates are parsed as Oman time and dd/mm is not confused with mm/dd', () => {
  const t = core.parse(messages[0], now).transactions[0]; assert.equal(t.occurredAt, '2026-10-25T08:00:05.000Z');
});
test('invalid dates, excess decimal precision and malformed balances fail closed', () => {
  for (const text of [messages[0].replace('25/10/2026', '31/02/2026'), messages[0].replace('80.000', '80.0009'), messages[0].replace('49.699', '49.6999')])
    assert.equal(core.parse(text, now).transactions.length, 0);
});
test('Arabic digits, separators, and exact baisa are supported', () => {
  assert.equal(core.money('١٬٢٣٤٫٥٦٧'), 1234567); assert.equal(core.money('0.001'), 1);
  assert.equal(core.money('0', true), 0); assert.equal(core.format(49699), '49.699');
  for (const value of ['1.2345', '-1', 'NaN', '1,23', '1e3', '', '9000000001']) assert.throws(() => core.money(value));
});
test('multiple messages without separators are not silently truncated', () => {
  assert.equal(core.parse(messages[0] + ' ' + messages[1], now).transactions.length, 0);
});
test('unsupported messages have no effect and remain visible as import errors', () => {
  const r = act('import', { text: 'Your OTP is 123456.\n\n' + messages[0] });
  assert.equal(r.result.added, 1); assert.equal(r.result.errors.length, 1);
});
test('allocation cannot exceed available bank funds', () => {
  const r = anchor(); assert.throws(() => act('envelope', { account, name: 'ادخار', kind: 'saving', amount: '100.001' }, r.state));
  const a = act('envelope', { account, name: 'ادخار', kind: 'saving', amount: '60' }, r.state);
  assert.equal(a.snapshot.accounts[0].available, 40000);
  assert.throws(() => act('envelope', { account, name: 'مصروف', kind: 'spending', amount: '41' }, a.state));
});
test('expense reduces both bank balance and pot remainder without double counting', () => {
  let r = act('envelope', { account, name: 'مصروف', kind: 'spending', amount: '60' }, anchor().state);
  const id = r.state.envelopes[0].id;
  r = act('manual', { account, kind: 'expense', amount: '10', envelopeID: id, date: '2026-10-26T12:01:00Z' }, r.state);
  assert.equal(r.snapshot.accounts[0].balance, 90000); assert.equal(r.snapshot.envelopes[0].remaining, 50000);
  assert.equal(r.snapshot.accounts[0].available, 40000);
});
test('refund replenishes assigned pot and is not counted as new income', () => {
  let r = act('envelope', { account, name: 'مصروف', kind: 'spending', amount: '60' }, anchor().state);
  const id = r.state.envelopes[0].id;
  r = act('manual', { account, kind: 'expense', amount: '10', envelopeID: id }, r.state);
  r = act('import', { text: messages[2] }, r.state);
  r = act('editTransaction', { id: r.state.transactions.find(t => t.kind === 'refund').id, envelopeID: id }, r.state);
  assert.equal(r.snapshot.envelopes[0].spent, 9375); assert.equal(r.snapshot.refunds, 625); assert.equal(r.snapshot.income, 0);
});
test('deleting a pot preserves transactions and clears their assignment', () => {
  let r = act('envelope', { account, name: 'مصروف', kind: 'spending', amount: '60' }, anchor().state);
  const id = r.state.envelopes[0].id;
  r = act('manual', { account, kind: 'expense', amount: '1', envelopeID: id }, r.state);
  r = act('deleteEnvelope', { id }, r.state); assert.equal(r.state.transactions.length, 1); assert.equal(r.state.transactions[0].envelopeID, null);
});
test('account balances and allocations are isolated', () => {
  let r = anchor(); r = act('anchor', { account: 'OTHER', amount: '5' }, r.state);
  assert.throws(() => act('envelope', { account: 'OTHER', name: 'آخر', kind: 'saving', amount: '6' }, r.state));
  assert.equal(r.snapshot.accounts.find(a => a.account === account).balance, 100000);
});
test('cross-account pot assignments are rejected', () => {
  let r = act('envelope', { account, name: 'مصروف', kind: 'spending', amount: '60' }, anchor().state);
  assert.throws(() => act('manual', { account: 'OTHER', kind: 'expense', amount: '1', envelopeID: r.state.envelopes[0].id }, r.state));
});
test('classification rules assign new transactions and warn at 80 percent', () => {
  let r = act('envelope', { account, name: 'تحويلات', kind: 'spending', amount: '100' }, anchor().state);
  const id = r.state.envelopes[0].id;
  r = act('rule', { keyword: 'PERSON A', category: 'عائلة', envelopeID: id }, r.state);
  r = act('import', { text: messages[0] }, r.state);
  assert.equal(r.state.transactions[0].category, 'عائلة'); assert.equal(r.snapshot.envelopes[0].percent, 80);
  assert.ok(r.snapshot.alerts.some(a => a.id === 'envelope-' + id));
});
test('low balance and monthly limit alerts are generated', () => {
  let r = imported(); r = act('settings', { lowBalance: '50', monthlyLimit: '300', warningPercent: 80 }, r.state);
  assert.ok(r.snapshot.alerts.some(a => a.id.startsWith('low-'))); assert.ok(r.snapshot.alerts.some(a => a.id.startsWith('monthly-')));
});
test('Oman month boundary is used for reports', () => {
  const r = act('manual', { account, kind: 'income', amount: '1', date: '2026-10-31T21:00:00Z' }, anchor().state, '2026-11-01T00:00:00Z');
  assert.equal(r.snapshot.month, '2026-11'); assert.equal(r.snapshot.income, 1000);
});
test('manual balance correction wins against an older SMS', () => {
  let r = anchor(); r = act('import', { text: messages[0] }, r.state); assert.equal(r.snapshot.accounts[0].balance, 100000);
});
test('internal transfer exclusion affects reporting, not bank balance', () => {
  let r = imported(); const id = r.state.transactions[0].id;
  r = act('editTransaction', { id, excluded: true }, r.state); assert.equal(r.snapshot.accounts[0].balance, 49699);
  assert.equal(r.snapshot.expenses, 207000);
});
test('backup round trip preserves state and rejects corrupt versions or amounts', () => {
  const a = imported(), b = act('restore', { data: JSON.stringify(a.state) }); assert.deepEqual(b.state, a.state);
  for (const corrupt of [{ ...a.state, version: 99 }, { ...a.state, transactions: [{ ...a.state.transactions[0], amount: -1 }] }])
    assert.throws(() => act('restore', { data: corrupt }, a.state));
});
test('operations do not mutate caller state when validation fails', () => {
  const s = anchor().state, original = JSON.stringify(s);
  assert.throws(() => act('manual', { account, kind: 'expense', amount: '-9' }, s)); assert.equal(JSON.stringify(s), original);
});
test('Swift Codable omits nil values: manual operations survive native serialization', () => {
  let r = act('manual', { account, kind: 'expense', amount: '10', date: '2026-10-26T12:01:00Z' }, anchor().state);
  const nativeState = JSON.parse(JSON.stringify(r.state, (_key, value) => value === null ? undefined : value));
  r = act('snapshot', {}, nativeState);
  assert.equal(r.snapshot.accounts[0].balance, 90000);
  const next = act('import', { text: messages[0] }, r.state);
  assert.equal(next.state.transactions.length, 2);
});
