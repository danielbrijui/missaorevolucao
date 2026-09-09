/* ==========================================================================
   Motor de alçadas — Missão Revolução (Estatuto v2, item 6.1 — set/2026)
   Fonte única das regras. Usado pelo app (navegador) e pelos testes (Node).
   Regras:
     6.1.3  quatro classes: ordinária / extraordinária / projeto orçada / projeto não orçada,
            julgadas pelo SALDO DA RUBRICA (não pelo total do orçamento)
     6.1.4  orçada (qualquer valor) → Presidente + Tesoureiro (conjunto)
     6.1.5  não orçada: ≤ 3.000 → Presidente + Tesoureiro; ≤ 15.000 → Conselho Diretor (maioria);
            > 15.000 → Assembleia Geral (maioria dos presentes, edital específico)
     6.1.6  Conselho Diretor = Presidente, Vice, Secretário, Tesoureiro; quem solicitou não vota;
            prazos 5 dias úteis (individual/conjunto) e 10 (colegiado); silêncio não aprova
     6.1.7  vedado fracionar
     6.1.8  pagamento só por Tesoureiro ou Presidente, mediante autorização de pagamento
     6.1.9  pago sem autorização prévia → ratificação (Conselho Diretor; Assembleia acima de 15.000)
     6.1.11 reembolso a diretor segue rota de não orçada; conflito de interesses (6.10) → Assembleia
   ========================================================================== */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.Alcadas = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const LIMITES = {
    PRES_TES: 3000,        // 6.1.5 a — não orçada até aqui: Presidente + Tesoureiro
    CONSELHO: 15000,       // 6.1.5 b — até aqui: Conselho Diretor; acima: Assembleia (6.1.5 c)
    PRAZO_INDIVIDUAL: 5,   // 6.1.6 — dias úteis
    PRAZO_COLEGIADO: 10,   // 6.1.6 — dias úteis
    ANTECEDENCIA_PROJETO: 90, // 6.1.2.1 — dias antes do projeto para aprovar o orçamento
    RESULTADO_PROJETO: 60,    // 6.1.12.1 — dias após o projeto para a reunião de resultados
  };

  const PAPEIS = {
    presidente: 'Presidente',
    vice: 'Vice-Presidente',
    secretario: 'Secretário',
    tesoureiro: 'Tesoureiro',
    conselho_fiscal: 'Conselho Fiscal',
    diretor_financeiro: 'Diretor Financeiro (contratado)',
    coordenador: 'Coordenador de Projeto',
    associado: 'Associado',
  };
  // Conselho Diretor (6.1.6): só os quatro cargos eleitos
  const DIRETORIA = ['presidente', 'vice', 'secretario', 'tesoureiro'];
  const PAGADORES = ['presidente', 'tesoureiro']; // 6.1.8

  const CLASSES = {
    ordinaria: 'Ordinária (orçada no orçamento anual)',
    extraordinaria: 'Extraordinária (não orçada)',
    projeto_orcada: 'De projeto, orçada',
    projeto_nao_orcada: 'De projeto, não orçada',
  };
  // compatibilidade com despesas lançadas na versão anterior do Estatuto
  const NATUREZAS = {
    ordinaria: 'Ordinária recorrente prevista no orçamento (aluguel, energia, serviços)',
    orcada: 'Prevista no orçamento anual (não recorrente)',
    projeto: 'Projeto aprovado em Assembleia',
    extraordinaria: 'Extraordinária (fora do orçamento e de projetos)',
  };

  const FORMAS = {
    pix: 'PIX', ted: 'TED/Transferência', boleto: 'Boleto', dinheiro: 'Dinheiro/Saque',
    cartao_debito: 'Cartão de débito', cartao_credito: 'Cartão de crédito',
  };

  const fmt = (v) => 'R$ ' + Number(v).toLocaleString('pt-BR', { minimumFractionDigits: 2 });
  const r2 = (v) => Math.round(v * 100) / 100;

  /**
   * @param {object} d
   *   valor               number
   *   projetoId           string|null   despesa de projeto?
   *   saldoRubrica        number|null   saldo disponível na rubrica do orçamento aprovado (anual ou do projeto);
   *                                     null = não há rubrica/orçamento aprovado → tudo não orçado
   *   reembolsoDiretor    boolean  (6.8.1 / 6.1.11)
   *   conflitoInteresse   boolean  (6.10)
   *   semAutorizacaoPrevia boolean (6.1.9) pagamento já efetuado, pede ratificação
   *   forma               chave de FORMAS
   * @param {object} ctx
   *   membrosDiretoria         nº de membros ativos do Conselho Diretor
   *   solicitanteNaDiretoria   boolean — o solicitante integra o Conselho (fica impedido, 6.1.6)
   *   temCoordenador           boolean — projeto tem coordenador cadastrado
   */
  function calcularRota(d, ctx) {
    ctx = ctx || {};
    const valor = r2(Number(d.valor) || 0);
    const etapas = [], alertas = [], bloqueios = [];
    if (!(valor > 0)) bloqueios.push('Valor deve ser maior que zero.');
    if (d.forma && !FORMAS[d.forma]) bloqueios.push('Forma de pagamento inválida.');
    if (bloqueios.length) return { etapas, alertas, bloqueios, assinatura: null, classe: null, orcado: 0, naoOrcado: valor, ratificacao: false };

    // ---------- classificação por rubrica (6.1.3) ----------------------------
    const saldo = d.saldoRubrica == null ? 0 : Math.max(0, Number(d.saldoRubrica));
    let orcado = Math.min(valor, saldo), naoOrcado = r2(valor - orcado);
    if (d.reembolsoDiretor) { orcado = 0; naoOrcado = valor; }               // 6.1.11
    const projeto = !!d.projetoId;
    const classe = projeto ? (naoOrcado > 0 ? 'projeto_nao_orcada' : 'projeto_orcada') : (naoOrcado > 0 ? 'extraordinaria' : 'ordinaria');
    const semOrc = d.saldoRubrica == null;

    // ---------- fábricas de etapas -------------------------------------------
    const n = Math.max(1, (Number(ctx.membrosDiretoria) || 4) - (ctx.solicitanteNaDiretoria ? 1 : 0));
    const maioria = Math.floor(n / 2) + 1;
    const conjunto = (base) => ({ papel: 'presidente_tesoureiro', rotulo: 'Presidente + Tesoureiro', base, tipo: 'conjunto', papeisAptos: ['presidente', 'tesoureiro'], quorum: 2, prazoDias: LIMITES.PRAZO_INDIVIDUAL });
    const conselho = (base) => ({ papel: 'conselho', rotulo: 'Conselho Diretor', base, tipo: 'colegiado', papeisAptos: DIRETORIA, quorum: maioria, membros: n, prazoDias: LIMITES.PRAZO_COLEGIADO });
    const assembleia = (base) => ({ papel: 'assembleia', rotulo: 'Assembleia Geral', base, tipo: 'assembleia', papeisAptos: ['presidente', 'secretario'], prazoDias: null });
    const coordenador = () => ({ papel: 'coordenador', rotulo: 'Coordenador do Projeto (atesta)', base: '6.1.4: solicitação do ADM Tesoureiro atestada pelo Coordenador — é do projeto e cabe no orçamento', tipo: 'individual', papeisAptos: ['coordenador'], porUsuario: true, prazoDias: LIMITES.PRAZO_INDIVIDUAL });

    // ---------- 6.1.9 ratificação de pagamento já efetuado -------------------
    if (d.semAutorizacaoPrevia) {
      const base9 = `6.1.9: pago sem autorização prévia (urgência/impossibilidade de comunicação) — ratificação ${valor > LIMITES.CONSELHO ? 'pela Assembleia Geral' : 'pelo Conselho Diretor'}; não ratificada, quem pagou restitui`;
      etapas.push(valor > LIMITES.CONSELHO ? assembleia(base9) : conselho(base9));
      alertas.push('Registre em até 5 dias úteis do pagamento, com justificativa e comprovante (6.1.9).');
      return { etapas, alertas, bloqueios, assinatura: null, classe, orcado, naoOrcado, ratificacao: true };
    }

    // ---------- 6.1.4 / 6.1.5 ------------------------------------------------
    if (projeto) {
      if (ctx.temCoordenador === false) alertas.push('Projeto sem Coordenador cadastrado — a etapa de atesto será pulada.');
      else etapas.push(coordenador());
    }
    if (naoOrcado <= 0) {
      etapas.push(conjunto(`6.1.4: ${CLASSES[classe]} — cabe no saldo da rubrica (${fmt(saldo)})`));
    } else {
      const motivo = d.reembolsoDiretor ? 'reembolso a membro da Diretoria/Conselho segue a alçada de não orçada (6.1.11)' : semOrc ? 'sem rubrica com orçamento aprovado' : `excede o saldo da rubrica (${fmt(saldo)}) em ${fmt(naoOrcado)}`;
      if (naoOrcado <= LIMITES.PRES_TES) etapas.push(conjunto(`6.1.5 "a": ${CLASSES[classe]}, parcela não orçada ${fmt(naoOrcado)} ≤ ${fmt(LIMITES.PRES_TES)} — ${motivo}`));
      else if (naoOrcado <= LIMITES.CONSELHO) etapas.push(conselho(`6.1.5 "b": parcela não orçada ${fmt(naoOrcado)} entre ${fmt(LIMITES.PRES_TES)} e ${fmt(LIMITES.CONSELHO)} — ${motivo}; maioria de ${n} membro(s) = ${maioria} voto(s)${ctx.solicitanteNaDiretoria ? ', solicitante impedido' : ''}`));
      else etapas.push(assembleia(`6.1.5 "c": parcela não orçada ${fmt(naoOrcado)} acima de ${fmt(LIMITES.CONSELHO)} — ${motivo}; Assembleia por maioria dos presentes, com a despesa no edital`));
    }
    if (d.conflitoInteresse && !etapas.some(e => e.tipo === 'assembleia')) {
      etapas.push(assembleia('6.10: contratação com conflito de interesses exige aprovação prévia da Assembleia; o diretor envolvido não vota'));
    }
    if (naoOrcado > 0 && orcado > 0) alertas.push(`Despesa mista: ${fmt(orcado)} dentro da rubrica e ${fmt(naoOrcado)} acima — a alçada da parcela não orçada vale para a despesa inteira (6.1.3.1).`);
    if (naoOrcado > LIMITES.PRES_TES) alertas.push('6.1.7: confira que a despesa não foi fracionada para caber em alçada menor.');
    return { etapas, alertas, bloqueios, assinatura: null, classe, orcado, naoOrcado, ratificacao: false };
  }

  return { LIMITES, PAPEIS, DIRETORIA, PAGADORES, CLASSES, NATUREZAS, FORMAS, calcularRota, fmt };
});
