# Mesa: protótipo jogável

Mesa virtual de RPG com mestre IA, feita em **Godot 4.7.2 com GDScript** (também roda no 4.3).
As regras são as do **D&D 5ª edição de 2024 pelo SRD 5.2.1** (licença CC-BY 4.0, pode vender).
O mestre ainda é provisório (padrões de texto); o modelo de IA local entra depois, no mesmo formato.

## Como abrir

1. Baixe o Godot 4.7.2 (versão padrão, não a .NET): https://godotengine.org/download/archive/4.7.2-stable/
2. Abra o Godot, clique em **Importar** e escolha o arquivo `project.godot` desta pasta.
3. Aperte **F5** para jogar.

O jogo abre em **preparação**: dá para criar personagens, subir de nível e descansar. Clique em
**Iniciar encontro** para rolar a iniciativa.

## Como uma sessão funciona

1. **Mesa:** cada mesa (aventura) fica em `data/adventures/<id>/` e escolhe um **tema**.
2. **Grupo:** usa os personagens pré-gerados da mesa ou os que vocês criarem (**+ Novo personagem**).
   Os criados ficam salvos por mesa na pasta de dados do usuário.
3. **Encontro:** iniciativa, turnos com a economia oficial, inimigos do SRD.
4. **Depois:** XP do encontro dividido, subida de nível pela ficha (aba **Nível**), descansos.

## O turno (SRD 5.2.1)

| Recurso | O que dá para fazer |
| --- | --- |
| Ação | Atacar (com Ataque Extra), conjurar (Magia), Disparada, Desengajar, Esquivar, Ajudar, Esconder, Preparar, Agarrar, Derrubar/Empurrar, Usar Objeto |
| Ação bônus | Características (Fúria, Retomar o Fôlego, Ação Ardilosa...), magias de ação bônus, segunda arma leve, Poção de Cura |
| Reação | Ataque de oportunidade, Escudo Arcano, Esquiva Sobrenatural, Desviar Ataques, ataque preparado. Volta no início do seu turno |
| Deslocamento | Divisível entre as ações. Caído rasteja pela metade; levantar custa metade |

Os indicadores no meio da barra mostram o que sobra (● disponível, ○ usado). Cartões apagados
dizem o motivo ao passar o mouse. Magias com mais de um nível de espaço abrem o seletor de nível
(e a Metamagia, para feiticeiros).

## Criação de personagem

Passo a passo do livro de 2024: **classe** (e subclasse a partir do nível 3), **origem**
(antecedente com +2/+1 ou +1/+1/+1, talento de origem; espécie e suas escolhas), **atributos**
(conjunto padrão, compra de 27 pontos ou 4d6), **perícias e equipamento** (opção A ou B),
**magias e opções** (truques, preparadas, estilo de luta, maestrias, ordens, Metamagia,
invocações, formas selvagens, aumentos de atributo) e **detalhes**. A ficha ao lado é calculada
ao vivo. Dá para começar em qualquer nível (1 a 20). Multiclasse está liberada na subida de nível
(pede 13 no atributo principal das duas classes).

## Temas e mesas

O tema **renomeia e filtra** o conteúdo sem mudar a regra. Ficam em `data/themes/`:

| Tema | O que muda |
| --- | --- |
| Fantasia clássica | Nada: nomes em português do conteúdo oficial |
| Místico | Fantasia sombria; algumas classes renomeadas (Arcanista, Pactuário, Juramentado...) |
| Cyberpunk | Classes, espécies, armas, armaduras, tipos de dano e monstros com nomes de tecnologia; moeda em créditos |
| Realista | Só humanos e classes sem magia (bárbaro, guerreiro, monge, ladino) |

Para criar uma mesa nova, copie `data/adventures/vale_cinzento/` e edite:

- `adventure.json`: título, sinopse, `theme`, faixa de nível e cenas. Cada cena tem fundo, pins,
  textos de abertura, vitória e derrota, posições iniciais do grupo e o encontro
  (`monster_id` de qualquer monstro do SRD, com nome e posição).
- `party.json`: personagens pré-gerados (as mesmas escolhas da tela de criação).
- `bible.json` e `quests.json`: o que o grupo sabe e as missões.

Para um tema novo, copie um arquivo de `data/themes/` e troque os nomes em `rename`; use `allow`
ou `deny` para esconder classes, espécies, talentos ou magias.

## O que o motor resolve sozinho

| Área | Automatizado |
| --- | --- |
| Testes de d20 | Vantagem e desvantagem (se anulam), crítico e 1 natural, Sorte halfling, Inspiração Heroica, Inspiração de Bardo, Talento Confiável, Exaustão |
| Combate | Iniciativa, economia de ações, Ataque Extra (até 4), segunda arma leve e Corte Rápido, Surto de Ação, ataque de oportunidade, ataque preparado, agarrar e empurrar |
| Condições | As 15 oficiais com efeito em ataques, salvaguardas e deslocamento; duração exata pela ordem de iniciativa; salvaguarda repetida no fim do turno |
| Dano e morte | Resistência, imunidade, vulnerabilidade, PV temporários, 0 PV, testes contra a morte, estabilizar, dano massivo, concentração (CD 10 ou metade do dano, máximo 30) |
| Maestrias | As 8: Trespassar, Raspar, Corte Rápido, Empurrar, Enfraquecer, Lentidão, Derrubar, Irritar |
| Magias | Espaços (incluindo multiclasse e Magia de Pacto), níveis acima, truques que crescem, um espaço por turno, concentração. 154 das 339 magias resolvem sozinhas por completo (ataque, salvaguarda em área com cone, linha, cubo, esfera e emanação, cura, bônus, marca, destruição, teleporte, reviver); outras 29 rolam a salvaguarda e o mestre aplica o efeito; as descritivas (Ilusão Menor, Mensagem...) o mestre arbitra |
| Classes | As 12, níveis 1 a 20, com subclasse. Fúria, Ataque Imprudente, Frenesi, Inspiração e Palavras Cortantes, Canalizar Divindade (Centelha, Expulsar, Preservar a Vida), Forma Selvagem com os animais do SRD, Retomar o Fôlego, Indomável, Crítico Aprimorado, Artes Marciais, Rajada de Golpes, Golpe Atordoante, Desviar Ataques, Cura pelas Mãos, Destruição Divina, Arma Sagrada, Aura de Proteção, Marca do Caçador, Matador de Colossos, Ataque Furtivo, Golpe Astuto, Esquiva Sobrenatural, Evasão, Feitiçaria Inata, Fonte de Magia, Metamagia (Acelerada, Duplicada, Elevada, Distante, Cuidadosa, Estendida), Rajada Agonizante, Bênção do Sombrio, Recuperação Arcana, Truque Potente, Esculpir Magias e outras |
| Espécies | Todas as 9, com resistências, sopro, Resistência Implacável, Bravura, Astúcia Gnômica, Ancestralidade Gigante |
| Monstros | Os 330 blocos do SRD (incluindo animais), Multiataque, recarga, sopros em área, Táticas de Matilha, Resistência à Magia, Resistência Lendária, Fortitude Morta-Viva, Fuga Ágil |
| Fora de combate | Descanso curto (Dados de Vida) e longo, XP por encontro, subida de nível |

Ainda com o mestre (o motor registra, o mestre narra): cobertura e linha de visão, terreno difícil,
quedas e saltos, montarias, familiares e invocações como criaturas separadas, ações lendárias e de
covil, magias de monstros, itens mágicos, viagem e exploração, peso carregado.

## Conversando com o mestre

Escreva o que o personagem quer fazer, do jeito que falaria na mesa: "quero tentar carisma para
transformar o goblin em aliado", "quero intimidar o hobgoblin", "pergunto onde estão os mineiros".
O mestre pede a perícia certa com CD pelo contexto e aplica a consequência. Clique num NPC para
escolher com quem está falando.

## Atalhos

| Tecla | Ação |
| --- | --- |
| 1 a 9 | Usar o cartão do grupo aberto (Ataques, Magias, Ações, Bônus) |
| M | Mover (ou clique no próprio token) |
| D | Esquivar |
| Enter | Confirmar alvos (Mísseis Mágicos, Bênção...) ou ir para o campo de texto |
| C | Abrir a ficha de quem joga |
| J | Diário |
| F8 | Modo streamer |
| Esc / botão direito | Fechar, cancelar mira ou movimento |

## Estrutura

```
data/srd/                SRD 5.2.1 em JSON (gerado por tools/srd_import.py)
data/i18n/pt_BR/         nomes e textos em português por cima do SRD
data/rules/              automação curada de magias
data/themes/             temas (renomear e filtrar)
data/adventures/<id>/    mesas: cenas, encontros, grupo pré-gerado, bíblia, missões
scripts/rules/
  srd.gd                 conteúdo, tradução e tema (autoload "Srd")
  rules.gd               regras puras: bônus, CA, deslocamento, dados, d20
  char_builder.gd        monta a ficha a partir das escolhas da criação
  monster_builder.gd     transforma bloco do SRD em criatura do motor
  combat.gd              ataques, dano, morte, condições, magias, características, descansos
  actions.gd             o que cada criatura pode fazer agora (para a barra e a IA)
scripts/core/
  game_state.gd          mesa, turnos, movimento, IA dos monstros (autoload "Game")
  master_mock.gd         mestre provisório (autoload "Master")
scripts/ui/              painéis; creator.gd é a criação e subida de nível
scripts/dev/             testes e prints
tools/                   importador do SRD e tradução (nomes e textos)
```

Regra da arquitetura: **a interface nunca altera o estado direto**, e **a IA narra, o motor decide**.

## Tradução

Todos os nomes estão em português (classes, espécies, magias, armas, itens, monstros e
características), e também as descrições: as 339 magias (com "Em nível superior" e "Melhoria
de truque"), todas as características de classe e subclasse, Metamagias, Invocações Místicas,
traços de espécie e talentos. Tempo de conjuração, alcance e duração aparecem em pt-BR e em
metros. Nos textos, o nome da classe segue o tema da mesa (no místico, "truques de Sacerdote").

Os textos ficam em `tools/i18n/texts_*.py`; rode `python3 tools/i18n/build_texts.py` para gerar
`data/i18n/pt_BR/texts.json` e ver a cobertura. O que não tiver tradução aparece no original em
inglês, com aviso. Tradução não oficial: não existe SRD oficial em português.

## Arte dos jogadores e placeholders

Pela ficha, aba **Aparência e efeitos**: retrato, token e uma imagem por ataque ou magia, com
animação automática pelo tipo. Arte do grupo em `assets/art/` (retratos por id, cenas 16:9,
ícones de condição por id do SRD, como `poisoned.png`; os nomes antigos em português continuam valendo).

## Ferramentas de teste

```
godot --headless --path . -- --rules-tests          # 110 testes de regra, combate e tradução
godot --path . -- --autoplay                         # combate jogado sozinho até o fim
godot --path . -- --creator-shots=/tmp/criacao       # cria e sobe de nível pela tela
godot --path . -- --shots=/tmp/prints                # prints das telas
godot --path . -- --dialog-shots=/tmp/dialogo        # diálogo, movimento e economia
godot --path . -- --fx-shots=/tmp/efeitos            # importação de arte e animações
```

Para atualizar os dados do SRD: `python3 tools/srd_import.py <pasta-do-markdown> data/srd`
e `python3 tools/i18n/build_names.py`.

## Licença do conteúdo de regras

This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1") by Wizards of
the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is licensed under the
Creative Commons Attribution 4.0 International License, available at
https://creativecommons.org/licenses/by/4.0/legalcode.

Essa atribuição precisa aparecer no jogo publicado (créditos). Não use as marcas "Dungeons & Dragons"
ou "D&D" no nome ou na divulgação; dá para dizer "compatível com a 5ª edição".

## Gerar o executável

No Godot: **Editor > Gerenciar modelos de exportação > Baixar**, depois
**Projeto > Exportar > Adicionar > Windows Desktop > Exportar projeto**.
