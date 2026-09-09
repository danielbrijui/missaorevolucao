// Testes do motor de alçadas (Estatuto v2). Rodar: node alcadas.test.js
const A = require('./alcadas.js');
let fails = 0, total = 0;
function caso(nome, d, ctx, esperado) {
  total++;
  const r = A.calcularRota(d, ctx);
  const papeis = r.etapas.map(e => e.papel).join('>');
  const bloq = r.bloqueios.length > 0;
  const ok = papeis === esperado.rota && bloq === !!esperado.bloqueado && (esperado.classe == null || r.classe === esperado.classe)
    && (esperado.naoOrcado == null || Math.abs(r.naoOrcado - esperado.naoOrcado) < 0.005) && (esperado.quorum == null || r.etapas.some(e => e.quorum === esperado.quorum)) && (esperado.ratificacao == null || r.ratificacao === esperado.ratificacao);
  if (!ok) { fails++; console.log('FALHOU', nome, { papeis, classe: r.classe, naoOrcado: r.naoOrcado, bloq, quorum: r.etapas.map(e => e.quorum), esperado }); }
  else console.log('ok   ', nome, '→', papeis || '(bloqueado)', '|', r.classe, '| não orçado', r.naoOrcado);
}
const base = { forma: 'ted' };
const ctx = { membrosDiretoria: 4, solicitanteNaDiretoria: false, temCoordenador: true };

// orçadas (6.1.4)
caso('ordinária 1.800 com saldo 5.000 → Pres+Tes', { ...base, valor: 1800, saldoRubrica: 5000 }, ctx, { rota: 'presidente_tesoureiro', classe: 'ordinaria', naoOrcado: 0 });
caso('ordinária 60.000 com saldo 60.000 → Pres+Tes (qualquer valor)', { ...base, valor: 60000, saldoRubrica: 60000 }, ctx, { rota: 'presidente_tesoureiro', classe: 'ordinaria' });
caso('projeto 4.000 com saldo 10.000 → coordenador > Pres+Tes', { ...base, valor: 4000, projetoId: 'p1', saldoRubrica: 10000 }, ctx, { rota: 'coordenador>presidente_tesoureiro', classe: 'projeto_orcada' });
// não orçadas (6.1.5) — julgadas pela parcela que excede a rubrica
caso('sem orçamento, 2.500 → Pres+Tes (a)', { ...base, valor: 2500, saldoRubrica: null }, ctx, { rota: 'presidente_tesoureiro', classe: 'extraordinaria', naoOrcado: 2500 });
caso('sem orçamento, 3.000,01 → Conselho (b)', { ...base, valor: 3000.01, saldoRubrica: null }, ctx, { rota: 'conselho', quorum: 3 });
caso('sem orçamento, 15.000 → Conselho (b, limite)', { ...base, valor: 15000, saldoRubrica: null }, ctx, { rota: 'conselho' });
caso('sem orçamento, 15.000,01 → Assembleia (c)', { ...base, valor: 15000.01, saldoRubrica: null }, ctx, { rota: 'assembleia' });
caso('rubrica saldo 2.000, compra 6.000 → excedente 4.000 → Conselho', { ...base, valor: 6000, saldoRubrica: 2000 }, ctx, { rota: 'conselho', classe: 'extraordinaria', naoOrcado: 4000 });
caso('rubrica saldo 2.000, compra 4.500 → excedente 2.500 → Pres+Tes', { ...base, valor: 4500, saldoRubrica: 2000 }, ctx, { rota: 'presidente_tesoureiro', naoOrcado: 2500 });
caso('projeto saldo 1.000, compra 20.000 → coordenador > Assembleia', { ...base, valor: 20000, projetoId: 'p1', saldoRubrica: 1000 }, ctx, { rota: 'coordenador>assembleia', classe: 'projeto_nao_orcada' });
// quórum e impedimento (6.1.6)
caso('Conselho com solicitante impedido: 3 membros votam, maioria 2', { ...base, valor: 8000, saldoRubrica: null }, { ...ctx, solicitanteNaDiretoria: true }, { rota: 'conselho', quorum: 2 });
caso('Conselho com 5 membros (cargo extra na Diretoria): maioria 3', { ...base, valor: 8000, saldoRubrica: null }, { ...ctx, membrosDiretoria: 5 }, { rota: 'conselho', quorum: 3 });
// regras especiais
caso('reembolso a diretor 300, mesmo orçado → rota de não orçada (Pres+Tes)', { ...base, valor: 300, saldoRubrica: 5000, reembolsoDiretor: true }, ctx, { rota: 'presidente_tesoureiro', naoOrcado: 300 });
caso('reembolso a diretor 5.000 → Conselho', { ...base, valor: 5000, saldoRubrica: 9000, reembolsoDiretor: true }, ctx, { rota: 'conselho' });
caso('conflito de interesses 1.000 orçado → Pres+Tes + Assembleia', { ...base, valor: 1000, saldoRubrica: 5000, conflitoInteresse: true }, ctx, { rota: 'presidente_tesoureiro>assembleia' });
// ratificação (6.1.9)
caso('pago sem autorização 900 → ratificação Conselho', { ...base, valor: 900, saldoRubrica: 5000, semAutorizacaoPrevia: true }, ctx, { rota: 'conselho', ratificacao: true });
caso('pago sem autorização 18.000 → ratificação Assembleia', { ...base, valor: 18000, saldoRubrica: null, semAutorizacaoPrevia: true }, ctx, { rota: 'assembleia', ratificacao: true });
// projeto sem coordenador cadastrado
caso('projeto sem coordenador → só Pres+Tes com alerta', { ...base, valor: 500, projetoId: 'p1', saldoRubrica: 2000 }, { ...ctx, temCoordenador: false }, { rota: 'presidente_tesoureiro' });
caso('valor zero → bloqueado', { ...base, valor: 0 }, ctx, { rota: '', bloqueado: true });

console.log(`\n${total - fails}/${total} casos ok`);
process.exit(fails ? 1 : 0);
