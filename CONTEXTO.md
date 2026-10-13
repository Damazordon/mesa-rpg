# Mesa Virtual de RPG — contexto para o Claude

Arquivo de contexto do projeto. Leia antes de mexer no código. Atualize a seção "Estado atual" ao fim de cada sessão.

## O que é
Mesa virtual de D&D feita por Gabriel e amigos. Executável em Godot, mestre narrado por LLM local (cínico, mas justo). Plano: vender na Steam.
Cada mesa tem um tema (místico, cyberpunk, realista, fantasia...) e uma história escritas por quem cria a sala. A IA gera a aventura a partir disso (tela de criação de sala). `vale_cinzento` continua como aventura fixa de exemplo.

## Como trabalhar
- Pasta no PC: `C:\Users\gabri\OneDrive\Documentos\mesa-prototipo-visual`. Altere os arquivos direto lá; o Gabriel só recompila.
- Godot **4.7.2** (GDScript). `trait` é palavra reservada (use `Rules.tv`).
- Classe nova com `class_name` → rodar `godot --headless --path . --import` antes de testar.
- Testes: `godot --headless --path . -- --rules-tests`. Em 12/out (rodado no Godot 4.7.2 Linux): regras 73, combate 110 (total), sala 99, terreno 55 — **0 falhas**. `RulesTests.run_room()` e `run_terrain()` são corrotinas: o `srd.gd` chama com `await`, senão o `quit` vem antes do fim. Erro de parse em qualquer script faz o teste travar sem sair (o `srd.gd` não compila): rode o `--import` primeiro e leia os erros. Prints: `--shots=`, `--creator-shots=`, `--autoplay`, `--map-shots=<pasta> [--biome=<id>]` (um print por bioma, névoa, prévia de caminho, cobertura e 4 rodadas de IA).
- Executável no PC do Gabriel: `C:\Users\gabri\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe` (não existe `godot` no PATH).
- Para o Claude, que não tem Godot: `pip install gdtoolkit --break-system-packages` dá o `gdparse`, que acha erro de **sintaxe** sem abrir o Godot. Ele não pega duas coisas que já quebraram a compilação aqui, então vale checar à parte: (a) `Classe.membro` que não existe, (b) `var`/`for` que **sombreia** nome de um escopo que o envolve (blocos irmãos podem reusar, aninhados não).
- Gravar arquivo no PC pelo Claude **pode falhar em silêncio** (a pasta está no OneDrive). Depois de gravar, puxar o arquivo de volta e comparar — já aconteceu de a resposta dizer "gravado" e o conteúdo no disco ser o antigo.
- Atalho: **`testar.bat`** na raiz do projeto faz import + testes e diz se passou. Funciona de qualquer pasta. No PowerShell, chamar o .exe direto exige o operador `&` antes do caminho entre aspas; o .bat evita isso.
- Responder em português. Não criar arquivos `.uid`.

## Decisões fixas
- Regras: **SRD 5.2.1 (2024)**, licença CC-BY-4.0 (atribuição no README e em `data/srd/LICENSE.txt`).
- Turno: economia oficial do D&D (ação, Ação Bônus, Reação, movimento, ação de Magia).
- Arquitetura: **"a IA narra, o motor decide"**. A interface nunca altera o estado direto; tudo passa por `Game.perform`.
- Unidades: 1,5 m = 5 pés (`Rules.m(ft) = ft*0.3`). Tabuleiro 32×18 m.
- Camadas de texto: SRD (inglês) → pt-BR (`data/i18n/pt_BR/names.json`, `texts.json`) → tema (rename de classes, `Srd.label`/`Srd.text`/`Srd.themed`).
- Sala: mesa local, um PC monta tudo. Aventuras geradas ficam em `user://adventures/<id>/` (`Game.adventure_dir` procura lá antes de `res://data/adventures/`). Grupo em `user://party_<id>.json`, capítulo atual em `settings["chapter_<id>"]`.
- Progressão: a missão **fixada** (`pinned`) tem exatamente um objetivo por capítulo, na ordem. `Game.complete_chapter_objective` marca pelo índice do capítulo — não quebre essa correspondência.
- Exploração (cenas com `pois`): o capítulo fecha ao **alcançar a saída**, não ao matar tudo. `Game.clear_chapter()` é o único caminho para fechar. Vencer um bando só libera caminho.
- Distâncias da descoberta (`Exploration`): 9 m = ponto pressentido ("?"), 4,5 m = descoberto com nome, 1,7 m = visitado. Bando escondido dispara em 5,5 m e o combate começa de onde todos estão.
- A saída começa fora do mapa (precisa ser descoberta) e só abre com todos os `required` visitados.
- Saque entra em `choices["equipment_extra"]` / `choices["gold_extra"]` e a ficha é reconstruída — é o que faz o saque sobreviver a salvar e carregar. Nunca escreva direto em `inventory`/`coins`.
- Cenas **sem** `pois` (a vale_cinzento) seguem no fluxo antigo: tudo visível e "Iniciar encontro" na mão.
- **A ordem da criação de sala é a de uma mesa real:** o mundo existe antes dos personagens. Sala → Aventura (lore) → Arte → Jogadores → a lore é reescrita com o grupo dentro. Por isso a aventura nasce sem fichas e o orçamento dos encontros vem de `cfg["player_count"]`, não da lista de fichas (`AdventureGen.party_size`).
- `adventure["lore"]` é **pública**: é o que os jogadores leem antes de criar personagem, e não pode ter segredo. Segredo vive na bíblia (`npcs`, `places`, `factions`), que é do mestre. `lore_base` guarda a versão antes da reescrita, para reescrever de novo não empilhar texto.
- A segunda passada (`AdventureGen.update_lore`) é **só texto**: não mexe em encontro, monstro nem XP, para a validação da primeira passada continuar valendo. Ela também recria as missões `pessoal_*` (removendo as antigas).
- Pedido de arte: campos estruturados (assunto, ambiente, luz, paleta), nunca prosa livre, mais o filtro `_banned_words` — nome de pessoa e de facção saem até palavra por palavra, título de aventura e de capítulo saem como frase, número sai sempre. **Nome de lugar fica**: é o que o mapa tem de mostrar. A lista vai embaralhada por hash, para não entregar a ordem dos capítulos.
- Chave da imagem de mapa: `scene["art_key"]` = `slug(nome da sala) + "_" + id da cena`. Não usa o id da aventura, senão regerar órfã as imagens já importadas.
- **Mapas: a IA não desenha.** Ela escolhe em `scenes[].terreno` um `bioma` e até 3 `feicoes` das listas fechadas de `MapGen.BIOMES`/`MapGen.FEATURES` (o resto é recusado). O motor gera o traçado com a semente da história, e é ele que posiciona grupo, saída, pontos e bandos, conferindo que tudo é alcançável a pé a partir do início, que os bandos ficam longe e, se der, fora da vista do início. Sem bioma da IA: palavra-chave do texto da cena, depois a lista do tema.
- Terreno é uma grade de 1 m (32 × 18) gravada em `scene["map"]["rows"]`: `.` chão, `#` parede, `T` coluna/árvore, `o` obstáculo baixo, `~` terreno difícil, `_` vão (água funda, abismo). `#`/`T` tapam a visão; `o`/`_` não. Cena **sem** `map` (vale_cinzento) = `TerrainMap` vazio = comportamento antigo idêntico. Sala gerada antes dos mapas ganha um ao carregar (`MapGen.ensure`, semente fixa da cena).
- Cobertura do SRD 5.2.1: meia +2, três quartos +5 (na CA e na salvaguarda de Destreza), total = não pode ser alvo. Calculada por retas de 3 pontos do atacante (pode se inclinar) a 3 do alvo; obstáculo baixo e criatura no meio dão meia; obstáculo colado no atacante não conta. Área de efeito não atravessa parede.
- Exploração com terreno: descobrir com nome, visitar e o bando notar o grupo pedem linha de visão; o "?" (9 m) não pede. Movimento (combate e exploração) segue caminho real, terreno difícil custa o dobro, inimigo bloqueia passagem.
- Desgaste é a dificuldade: PV, recursos e Dados de Vida **não** voltam ao passar de capítulo. Descanso longo só nos `rest_points` da aventura quando `settings["rest_mode"] == "aventura"`.
- Subir de nível: `settings["level_mode"]` = `"xp"` (padrão, exige XP) ou `"marco"` (o mestre libera). A XP de uma ficha nunca fica abaixo do mínimo do próprio nível.

## Mapa do código
- Autoloads, nesta ordem: `Srd` → `Game` → `Master`.
- `scripts/rules/`:
  - `srd.gd`: dados, tradução, tema, `spell_meta` e `spell_text`.
  - `rules.gd`: cálculos estáticos (CA, salvaguardas, dados, recursos).
  - `char_builder.gd`: monta o PC a partir das escolhas.
  - `monster_builder.gd`: monta os monstros.
  - `combat.gd`: ataques, magias, dano, condições, efeitos, descansos.
  - `actions.gd`: lista de atividades disponíveis por criatura.
- `scripts/core/`:
  - `game_state.gd`: aventura, grupo, turnos, movimento, IA dos NPCs, `create_room` (grava e carrega a sala).
  - `room_builder.gd`: regras da tela de sala (temas, ideias de história, compra de pontos, preenchimento automático da ficha, validação).
  - `adventure_gen.gd`: gera a aventura com a IA e o motor valida (monstros do SRD, orçamento de XP, posições); sem IA monta um modelo.
  - `exploration.gd` (`Game.ex`): exploração do capítulo — descoberta por distância e visão, saque, emboscada dos bandos escondidos e saída.
  - `terrain_map.gd` (`Game.terrain`): grade, caminho (A* alisado), custo, linha de visão (percurso exato da grade), cobertura, campo de distância e células vistas. Tudo em metros.
  - `map_gen.gd`: biomas, feições, briefing da IA, geradores (caverna, salas, ar livre, cidade) e o posicionamento validado (`layout`, `ensure`).
  - `icon_store.gd` (`GameIcons`): lê `data/icons.json` e devolve a textura do ícone de arma/perícia (`attack_texture`, `weapon_texture`, `skill_texture`, `rect` para pôr numa linha). Arma sem ícone próprio cai no genérico corpo a corpo/à distância; golpe desarmado tem o seu; ataque sem arma (mordida) não tem.
  - `art_store.gd`: arte importada pelo jogador (`portraits`, `tokens`, `fx`, `monsters`, `scenes`). "scenes" é o único que não entra no corte quadrado.
  - `master_mock.gd`: narração do mestre (mock da LLM).
- `scripts/ui/`:
  - Combate e mapa: `action_bar`, `map_view`, `terrain_painter` (imagem assada do terreno por bioma, objetos em vetor, névoa).
  - Ficha e criação: `character_sheet` (7 abas), `creator` (criação e subida de nível).
  - Painéis: `party_*`, `top_bar` (botão "Nova sala").
  - Criação de sala: `room_setup` (3 etapas: Sala, Jogadores, Aventura). Abre ao iniciar o jogo sem argumentos; "Continuar mesa atual" segue a última.
  - Lore em papel, escrita na frente de quem lê: `lore_book` (`LoreBook.write`).
  - Entre capítulos: `chapter_panel` (balanço do capítulo, PV do grupo, descanso, "Próximo capítulo").
- `data/`:
  - `srd/*.json` (gerado por `tools/srd_import.py`; não editar à mão).
  - `adventures/vale_cinzento/` (aventura de exemplo).
  - `themes/`, `conditions.json`.
  - `rules/spells_auto.json` (automação de magias curada).
- `tools/i18n/`: `texts_*.py` → `python3 tools/i18n/build_texts.py` gera `texts.json`.

## Próximos passos decididos (12/out, ordem do Gabriel)
1. ~~Mapas por tema~~ — feito em 12/out (ver Estado atual).
2. **Tradução do que falta** (pedido explícito): ações e traços dos 330 monstros, antecedentes, itens e glossário, pelo pipeline `tools/i18n/` (`texts_*.py` → `build_texts.py`). É volume de dados, em lotes.
3. ~~Ícones de armas e perícias~~ — feito em 12/out (ver Estado atual e "Ícones" abaixo).
4. **Equipado vs mochila** (detalhes abaixo).
5. **Retrato de criatura no jogo.** `ArtStore.monster_image(id)` já existe e a importação já funciona, mas nada no jogo desenha esse retrato ainda: ligar no token do mapa, no cartão de quem passa o mouse e na ficha do monstro.
6. **Token e moldura na ficha:** a infraestrutura é a mesma dos pedidos de arte, falta expor.
7. **Armas sob medida** e 8. **dados 3D** (detalhes abaixo).
Ainda de fora: ações lendárias, magias de monstro, itens mágicos e invocações de criaturas.

Detalhes:
- **Equipado vs mochila.** "Começa com muitas armas" é o kit do SRD (guerreiro A traz espada grande, mangual e 8 azagaias), não defeito: o problema é toda arma carregada virar ataque na barra. A correção são slots (mão principal, secundária, à distância), **não** peso — peso não limita poder, quem limita é nível, opção de equipamento e ouro. Se for fazer carga, usar a regra oficial (Força × 7,5 kg + Sobrecarga) como regra opcional. O objetivo do Gabriel (dificuldade e sensação de progresso) já é atendido pelo desgaste entre capítulos.
- **Ícones:** game-icons.net (CC-BY 3.0), tabela id → ícone em `tools/icons/icon_map.py`; `python3 tools/icons/build_icons.py <clone de github.com/game-icons/icons>` copia os SVG para `assets/icons/game-icons/` (sem o fundo preto, traço branco para tingir com `modulate`) e grava `data/icons.json` e `CREDITS.txt`. Atribuição no README e nos créditos do jogo publicado. Ainda sem ícone: armaduras, itens de equipamento, magias, ações genéricas.
- **Importar token e moldura:** estender `art_store.gd` com `FileDialog`, cópia para `user://art/` e molduras como estilo.
- **Armas sob medida:** chassi de arma do SRD + um adorno de catálogo fechado com custo em pontos. A IA escreve nome e sabor; **o motor aplica o teto** (modelo de 4B não julga equilíbrio).
- **Arte de inimigos por IA:** ComfyUI local (API HTTP, como o Ollama). Na RTX 5050 (8 GB): SDXL base 1.0 ou SD 1.5 (licenças OpenRAIL, uso comercial permitido); FLUX.1-schnell é Apache 2.0 e cabe quantizado. **Evitar SDXL-Turbo e FLUX.1-dev: não comerciais.** A arte vai no jogo vendido, então gerar na fase de desenvolvimento e empacotar os PNGs — geração em tempo de jogo exigiria ComfyUI em cada comprador.
- **Dados caindo no tabuleiro:** `RigidBody3D` num `SubViewport` sobre o tabuleiro 2D. A física **não decide** o número: `Rules.d20` já decidiu e a animação só mostra, senão descola das regras e dos testes.

## Estado atual (12/out/2026)
**Pronto:**
- **Mapas por tema** (12/out; testes no Godot 4.7.2: 55 de terreno, e os 282 antigos seguem verdes; prints conferidos por bioma; **nunca jogado com mouse**). 13 biomas (caverna, mina, masmorra, interior, instalação, esgoto, floresta, pântano, ruínas, campo, deserto, cidade, metrópole) com visual próprio; 13 feições (rio, ponte, lago, abismo, pilares, caixotes, barricadas, entulho, lama, mato, areia, árvores, ruínas). Geração por capítulo: 30 a 140 ms. No tabuleiro: imagem assada do terreno, colunas/árvores/caixotes em vetor, névoa (nunca visto quase preto, já visto meio escuro, à vista limpo; alcance de visão por bioma), prévia tracejada do caminho com custo, área alcançável pintada no modo de movimento, legenda da célula sob o ponteiro, inimigo fora da vista do grupo some do tabuleiro, cartão do mouse mostra cobertura. A IA dos inimigos anda por caminho, procura lugar à vista para atirar e só usa sopro em quem vê. Empurrão para na parede; Passo Nebuloso exige ver o destino. Ataque de oportunidade vale para o trajeto inteiro (passar ao lado e seguir provoca). A tela de sala mostra o bioma de cada capítulo (e agora lista os monstros dos bandos, que antes saía vazio).
- Criação de personagem e subida de nível para as 12 classes, multiclasse e talentos.
- Combate oficial completo: reações, concentração, morte, áreas e IA dos inimigos.
- Automação de magias: 154 completas e 29 parciais.
- Descansos.
- Tradução pt-BR de todos os nomes, das 339 magias, de todas as características de classe e subclasse, de metamagias, invocações, traços de espécie e talentos.
- Mestre com IA local (escrito em 12/out, **ainda não testado no Godot**): `scripts/core/master_llm.gd` (autoload `Master`) estende o `master_mock.gd`. Fala com o Ollama (constante `MODEL`, hoje `qwen3.5:4b`, `http://127.0.0.1:11434`). A IA só escolhe uma intenção do catálogo de `master_lines.json` e escreve os textos; CD, alvo e efeitos continuam do motor. Se o Ollama falhar ou responder lixo, cai no mock.
- 3 níveis de mestre (seletor "Mestre:" na `top_bar`, salvo em `settings["master_level"]`): Calmo (CD -2), Normal (CD +0), Cínico (CD +2; na falha o jogador leva 1d4 de dano e o mestre provoca). Constantes em `Master.LEVELS`.
- Exploração do capítulo (escrita em 12/out, **lógica testada, nunca jogada**): o capítulo começa vazio. Cada jogador move seu token clicando (`map_view._click_explore` → `Game.ex.explore_move`), e o motor revela pontos de interesse, saqueia baús ao chegar e dispara os bandos escondidos. Pontos de interesse: `exit` (uma, escondida), `mark` (1 a 2, obrigatórios) e `chest` (1 a 2, com moedas e equipamento mundano do SRD). A IA escreve nome, texto e a frase de cada emboscada; posição, conteúdo e distâncias são do motor. "Iniciar encontro" fica escondido nesses capítulos.
- Progressão de capítulos (escrita em 12/out, testada em 12/out): a sala gera de 1 a 5 capítulos em arco, com orçamento de XP em escalada (`AdventureGen.CHAPTER_RAMP`: 70%, 100%, 115%, 130%, 150% do base). O chefe fica só no último. Vencido o encontro, o motor marca o objetivo do capítulo, soma a XP e o `chapter_panel` mostra o balanço (PV do grupo, quem pode subir, descanso, próximo capítulo). `Game.advance_chapter` troca de cena preservando PV e recursos, estabiliza quem estava caído com 1 PV e recarrega a tela principal. A aventura tem `epilogue` e `rest_points`.
- Experiência corrigida (12/out): a XP já era somada (`combat.gd`, ao derrubar inimigo) e distribuída na vitória, mas (a) ficha criada no nível 3 nascia com 0 XP, então a faixa nunca alcançava o nível seguinte, e (b) o botão "Subir de nível" ignorava a XP — era o passe livre. Os dois corrigidos, com `level_mode` para quem preferir marcos.
- Criação de sala (escrita em 12/out, **ainda não compilada nem testada no Godot**): tela `RoomSetup` com nome, tema, história, nível inicial (1 a 5), pontos de atributo (padrão 27, ajustável; cada jogador distribui), dificuldade e nível do mestre; por jogador: personagem, classe, espécie, antecedente, cor do token, atributos, origem, história e objetivo pessoal (vira missão). "Ficha completa" abre o `CharacterCreator` (`open_edit`). Faltas da ficha são preenchidas por `RoomBuilder.autofill`. A IA gera título, sinopse, cena, missões e NPCs; o motor só aceita monstros do SRD que cabem no orçamento de XP e posiciona os tokens. `Master` recebe a premissa da sala no prompt.

- Ícones de armas e perícias (12/out, **não compilado nem testado no Godot; só `gdparse` passou**): 56 SVG do game-icons.net (38 armas, 18 perícias, 3 genéricos), cobrindo todas as armas de `weapons.json` e as 18 perícias. Aparecem no cartão de ataque da `action_bar` (canto inferior direito), na lista de ataques e nas perícias da `character_sheet`. Teste novo `RulesTests.run_icons()` (chamado no `srd.gd` depois do terreno): toda arma/perícia tem ícone, arquivo existe, textura carrega e o autor consta em `CREDITS.txt`.

**Pendente / limitações conhecidas:**
- Ícones: rodar `--import` e `testar.bat`, e olhar o cartão de ataque (o ícone divide o cartão de 150 px com o nome; nome comprido pode ficar apertado) e a aba de perícias (linha passou de 270 para 300 px). Alguns ícones são aproximações (lança/javelin, cimitarra, florete, azagaia, zarabatana): trocar em `icon_map.py`. **Os SVG gravados no PC ganharam um bloco `<metadata>` C2PA (~8 KB cada) injetado pela ferramenta de envio**; `GameIcons` ignora isso no fallback e deve funcionar no import, mas para ter os arquivos limpos rode o `build_icons.py` localmente.
- Sala e progressão: rodar `--import` (há classe nova, `ChapterPanel`) e os testes; depois jogar uma aventura de 3 capítulos de ponta a ponta com o Ollama. A tabela de orçamento de XP (`AdventureGen.XP_BUDGET`) foi escrita de memória: conferir no livro. Sem rede/lobby online.
- Mapas: jogar com mouse e conferir (1) se a névoa não esconde demais (visão de 9 a 16 m por bioma, em `MapGen.BIOMES[...]["vision_m"]`), (2) se a prévia do caminho não pesa ao mexer o mouse (recalcula só quando o ponteiro muda de lugar), (3) se 5,5 m + linha de visão deixa o bando escondido de verdade. Arte importada de mapa não conhece o traçado: o terreno vai por cima a 35% de opacidade. Saída para casar arte e traçado: exportar o mapa gerado e usar como ControlNet no ComfyUI. Criatura caída do grupo ainda conta para a névoa. A vale_cinzento continua sem terreno (de propósito).
- Criação de sala em 5 etapas, lore pública, pedidos de arte e livro sendo escrito (12/out, **lógica testada, nunca aberta na tela**). O que eu olharia: se o `FileDialog` abre e importa, se o mapa importado aparece no tabuleiro, se a animação do livro não fica lenta com lore longa, e se a segunda passada da IA não demora demais (é uma segunda chamada ao Ollama).
- Exploração: nunca foi jogada. Conferir se dá para entender onde ir (a saída é escondida; o "?" a 9 m é o que evita andar às cegas). Alcançabilidade dos pontos e bando fora da vista do início agora são garantidos e testados pelo motor.
- Mestre IA: testar de verdade (`ollama pull qwen3:8b`), ajustar prompts e comparar com `qwen3:4b` e Gemma. A IA ainda não narra o resultado livremente nem cria efeitos próprios (só usa o catálogo de intenções). O dano do nível Cínico é fixo (1d4, sem tipo) e vale para qualquer falha de teste.
- Texto dos monstros (ataques e traços) ainda em inglês. É o próximo passo sugerido.
- Antecedentes, itens e glossário ainda em inglês.
- Sem ações lendárias, sem magias de monstros, sem itens mágicos e sem invocações de criaturas.
- Conferir no PDF as tabelas escritas de memória: Confusão, Palavra Divina, Spray e Muralha Prismática, Reencarnação, Vidência, Criação, Controlar o Clima. Teletransporte entrou só como resumo.
