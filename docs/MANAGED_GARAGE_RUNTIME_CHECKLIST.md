# Checklist runtime de garagens administradas

Itens nao executados devem permanecer desmarcados.

## Preparacao

- [ ] Usar staging local/descartavel; nao usar producao ou VPS.
- [ ] Fazer backup recuperavel do banco de staging.
- [ ] Iniciar `oxmysql`, `ox_lib`, `mz_core`, `mz_vehicles`, `mz_fuel`, `mz_interact`, `mz_menu`, `mz_garagem` e `mz_admin`.
- [ ] Confirmar no console o repositorio pronto e a quantidade de garagens administradas carregadas.
- [ ] Conceder `staff.panel.open` e `staff.garages.create` somente ao Staff de teste.

## Criacao publica

- [ ] `/admin` mostra `Gerenciar garagens`.
- [ ] Deixar o nome vazio gera `Garagem Pública` no menu e no blip.
- [ ] Criar um rascunho publico em duas etapas.
- [ ] Abrir `Posicionar todos os pontos`, andar/dirigir livremente, alternar trava com `G` e capturar cada etapa com `E`.
- [ ] Confirmar que `G` trava o ped a pe e destrava ao pressionar novamente.
- [ ] Confirmar que `G` trava o veiculo somente no banco do motorista.
- [ ] Confirmar que capturar, cancelar e reiniciar `mz_admin` nunca deixam ped ou veiculo travado.
- [ ] Confirmar que o menu volta sozinho depois da ultima captura.
- [ ] Cancelar uma captura com `X` e confirmar que o menu volta sem apagar pontos anteriores.
- [ ] Reposicionar individualmente entrada, spawn e armazenamento.
- [ ] Concluir e confirmar notificacao de sincronizacao.
- [ ] O ponto aparece sem reiniciar resources.
- [ ] Abrir, retirar e guardar um veiculo compativel.
- [ ] Reiniciar `mz_garagem` e confirmar que a garagem reaparece.

## Criacao organizacional

- [ ] O seletor mostra apenas organizacoes ativas.
- [ ] Deixar o nome vazio gera `Garagem - <nome da organizacao>`.
- [ ] Criar garagem para uma organizacao de staging.
- [ ] Membro correto abre a garagem.
- [ ] Nao membro recebe negacao.
- [ ] Com `requireDuty=true`, membro fora de duty recebe negacao e em duty abre.
- [ ] Com `primaryOnly=true`, membership nao primaria recebe negacao.
- [ ] Cargo abaixo de `minGradeLevel` recebe negacao.
- [ ] Organizacao arquivada entre selecao e confirmacao e recusada pelo servidor.

## Negativos

- [ ] Sem `staff.garages.create`, o modulo nao aparece.
- [ ] Callback/export chamado diretamente sem permissao retorna `permission_denied`.
- [ ] Codigo duplicado de garagem estatica e recusado.
- [ ] Codigo duplicado persistente e recusado.
- [ ] Pontos separados por mais de 250 metros sao recusados.
- [ ] Parada de `mz_core`, `oxmysql` ou falha do repositorio nao libera criacao.
- [ ] Membership/capability organizacional nao concede `staff.garages.create`.
- [ ] Staff com apenas `staff.garages.view` lista, mas nao cria, edita ou arquiva.
- [ ] Staff com `staff.garages.manage` sem `view` nao recebe listagem implicitamente.
- [ ] Tentativas de trocar codigo, tipo ou organizacao na edicao sao recusadas.

## Edicao e ciclo de vida

- [ ] `Garagens cadastradas` lista ativas e arquivadas.
- [ ] Editar nome atualiza menu e blip sem restart.
- [ ] Limpar o nome restaura o label padrao.
- [ ] Editar regras preserva codigo, tipo e organizacao.
- [ ] Reposicionar um ponto remove o ponto antigo e registra o novo sem duplicidade.
- [ ] Arquivar remove interacao, marker e blip sem apagar a linha.
- [ ] Reativar restaura interacao, marker e blip.
- [ ] Reiniciar `mz_garagem` preserva o estado ativo/arquivado.

## Frota de servico

- [ ] Retirar e guardar uma viatura de servico no ponto correto.
- [ ] Permanecer mais de 30 segundos com a viatura fora e ainda conseguir guarda-la.
- [ ] Com uma viatura ativa, uma segunda retirada da mesma frota e recusada.
- [ ] Um veiculo persistente da organizacao no ponto de servico e recusado com mensagem clara.
- [ ] A viatura so e aceita com o runtime ativo, a placa da retirada e a entidade presente.
- [ ] Tentativa com placa, entidade ou garagem divergente e recusada sem consumir o runtime.
- [ ] Agente fora de servico consegue devolver uma viatura de servico que ainda esta vinculada a ele.
- [ ] Depois de guardar, o acesso temporario da viatura e revogado e a entidade some do mundo.
- [ ] Dano, combustivel, tuning e estado de destruicao sao preservados por personagem ao guardar.
- [ ] Outro personagem que retira a mesma entrada recebe o proprio estado, nao o do primeiro.
- [ ] Reiniciar `mz_garagem` recarrega o estado persistente da frota do banco.
- [ ] Com `persist_state=false`, a retirada volta a usar os defaults da frota.
- [ ] Reiniciar `mz_garagem` com viatura fora exige nova retirada; o runtime antigo nao e aceito.

## Regressao

- [ ] Garagens estaticas publicas continuam abrindo.
- [ ] Garagens estaticas de organizacao continuam aplicando acesso.
- [ ] Garagens de servico continuam funcionando.
- [ ] Garagens de casas continuam registrando e removendo sessao.
- [ ] `mz_interact` nao mantem pontos duplicados depois de sincronizar.
- [ ] Com fallback legado, marker e blip dinamicos aparecem corretamente.

## Evidencia

Para cada caso, registrar identidade, grants globais, codigo da garagem, organizacao quando aplicavel, valores escolhidos, resultado observado e trecho de console. Nao marcar como aprovado sem execucao runtime.
