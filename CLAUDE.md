# stagelatch

Quality gate *change-aware* para repositórios Flutter/Dart. Um único motor com dois pontos de entrada:

- **Hook local:** pre-commit e pre-push.
- **CI:** pull request.

Avalia o snapshot do **index**, ou seja, exatamente o que vai para o commit, com semântica Dart e só no escopo afetado.

Distribuído como CLI no pub.dev (`dart pub global activate stagelatch`). Projeto de portfólio: qualidade de engenharia, decisões documentadas e casos de borda resolvidos importam mais que quantidade de features.

## Idioma

- Conversa comigo: português, direto, sem introduções.
- Em inglês: código, identificadores, comentários, mensagens de commit, README, CHANGELOG, docs públicas e mensagens do CLI.

## Decisões fixas (ADRs a registrar em `docs/adr/`)

1. **Validar o index, não o working tree.**
   - Blobs lidos por um processo `git cat-file --batch` persistente: um spawn, não um por arquivo.
   - Análise com `package:analyzer` + `OverlayResourceProvider`.
   - O overlay recebe a versão do index de **todo** arquivo que diverge entre index e working tree (`git diff --name-only -z`), não só dos staged. Sem isso, mudanças não staged contaminam a análise.
   - Nunca usar stash.
2. **Autofix seguro.**
   - Grava o blob corrigido no index (`git hash-object -w --stdin` + `git update-index --cacheinfo <mode>,<sha>,<path>`).
   - Só reescreve o arquivo no disco se ele não tiver mudanças unstaged.
3. **Determinístico. Nenhuma IA no caminho de bloqueio.**
   - Sem rede.
   - Mesmo input, mesmo resultado em qualquer máquina e no CI.
4. **Distribuição via `pub global activate`, nunca como dev_dependency.** O `analyzer` entraria no version solving do projeto e conflitaria com freezed, json_serializable e build_runner.
5. **Mesmo motor para hook e CI.**
   - O hook local é feedback rápido.
   - A garantia é o `stagelatch ci` no pull request.
6. **Hooks são gatilhos finos, sem lógica.** Se o executável não estiver instalado, o hook avisa e **não bloqueia**, porque o CI é a garantia:
   ```sh
   #!/bin/sh
   # stagelatch:managed
   command -v stagelatch >/dev/null 2>&1 || {
     echo "stagelatch not found; skipping. Install: dart pub global activate stagelatch" >&2
     exit 0
   }
   exec stagelatch run pre-commit "$@"
   ```

## Arquitetura

```
lib/src/
├── domain/          # Check, Finding, Severity, Location, ChangeSet, Fix — sem dependência de git/analyzer/IO
├── application/     # Pipeline, seleção de checks por hook, scheduler, orçamento de tempo, Baseline, ConfigLoader
├── infrastructure/  # GitClient, AnalyzerWorkspace, DartStyleFormatter, PubspecReader, reporters, HookInstaller
└── cli/             # comandos (package:args CommandRunner)
```

- Checks recebem um `CheckContext` (leitura de blobs, sessão do analyzer, pubspec parseado, config) e retornam findings. Não conhecem git, analyzer nem IO diretamente.
- IDs de regra no formato `<check>/<rule>`, por exemplo `pubspec/path-dependency`. São estáveis, documentados e usados em config, ignore e baseline.
- Fingerprint do baseline: `ruleId + path + hash do trecho normalizado`. Nunca número de linha.
- Locations com linha e coluna. YAML lido com `package:yaml` preservando os source spans.
- `HookInstaller`:
  - respeita `core.hooksPath`, porque husky e lefthook o alteram;
  - não sobrescreve hooks de terceiros sem `--force`, e faz backup quando sobrescreve.

## CLI

| Comando | Função |
|---|---|
| `stagelatch init` | detecta stack, gera `stagelatch.yaml`, instala hooks |
| `stagelatch install` | só instala hooks (por clone) |
| `stagelatch run <hook>` | executa os checks do hook sobre o index |
| `stagelatch ci --base <ref> --reporter <console\|github\|junit\|sarif>` | mesmo motor sobre o diff do PR |
| `stagelatch baseline create\|prune` | adoção em projeto legado |
| `stagelatch why <test-file>` | explica a seleção de teste afetado |

Exit codes:

| Código | Significado |
|---|---|
| `0` | passou |
| `1` | findings bloqueantes |
| `64` | uso incorreto |
| `70` | erro interno |
| `78` | config inválida |

## Config (`stagelatch.yaml`)

```yaml
min_version: 0.1.0

hooks:
  pre-commit: [format, analyze, codegen, pubspec, l10n, assets, sensitive-files, tests.solo]
  pre-push: [analyze, tests.affected]

format:
  fix: true

analyze:
  scope: affected
  fail_on: [error, warning]

codegen:
  generated_files_committed: true

pubspec:
  forbid: [path-dependencies, dependency-overrides, unpinned-git]
  monotonic_build_number: [release/*]

l10n:
  missing_keys: error
  placeholder_mismatch: error
  unused_keys: warning

assets:
  max_file_size: 500KB
  ignore: [assets/videos/**]

baseline: .stagelatch/baseline.json
```

## Catálogo de regras

| Check | Regras |
|---|---|
| `format` | `unformatted` |
| `analyze` | código do diagnóstico do analyzer |
| `codegen` | `stale`: diff de AST HEAD vs index das declarações anotadas sem o `.g.dart`/`.freezed.dart` correspondente staged |
| `pubspec` | `path-dependency`, `dependency-overrides`, `unpinned-git`, `build-number-regression` |
| `l10n` | `missing-key`, `placeholder-mismatch`, `unused-key` (lê `l10n.yaml`) |
| `assets` | `missing`, `undeclared`, `max-file-size` |
| `sensitive-files` | `signing` (`key.properties`, keystores, `.p8`/`.p12`), `credentials` (service account JSON, `.env*`) |
| `tests` | `solo`, `new-skip`, `affected` (pre-push) |

## Roadmap

0. **Spike (primeiro, antes da arquitetura definitiva).**
   - Medir `OverlayResourceProvider` com conteúdo do index num app Flutter grande e real, num commit típico de 3 a 10 arquivos.
   - Meta: abaixo de ~2 s. Se não atingir, avaliar um processo persistente (daemon) antes de seguir.
1. **`0.1.0-dev.1`**, para reservar o nome no pub.dev; deliberadamente sem analyzer.
   - `init`, `install`, `run pre-commit`.
   - `GitClient` com `cat-file --batch`.
   - Checks `pubspec/path-dependency` e `pubspec/dependency-overrides`.
   - Reporter de console.
   - Testes de aceitação.
2. **`0.1.0`**
   - `format` com autofix seguro.
   - `analyze` afetado com overlay.
   - `sensitive-files`.
   - `ci --base` com reporter `github`.
   - Benchmark reproduzível no README e GIF de terminal gravado com VHS.
3. **`0.2.0`:** `codegen`, `l10n`, `assets`, `pubspec` completo, `tests.solo`, baseline.
4. **`0.3.0`:** `tests.affected` (grafo de imports por parse de diretivas), cache por hash de conteúdo, reporters SARIF e JUnit, pub workspaces.
5. **`1.0.0`:** API pública para checks customizados. Só então avaliar separar um `stagelatch_core`.

## Padrões de engenharia

- **Lints:** `very_good_analysis` com `strict-casts`, `strict-inference` e `strict-raw-types`. Zero warnings.
- **Testes:**
  - Unitários no domínio e na aplicação.
  - **Aceitação com repositórios git reais** criados em diretório temporário.
  - Cenários obrigatórios:
    - staging parcial (`git add -p`);
    - rename, delete, arquivo binário;
    - primeiro commit (sem HEAD);
    - merge e rebase em andamento;
    - `core.hooksPath` já configurado por outra ferramenta;
    - CRLF;
    - paths com espaço e unicode.
- **CI:** matriz Dart stable e beta × ubuntu, macos e windows.
- **Release:**
  - Conventional Commits.
  - `release-please` para versão e CHANGELOG.
  - Publicação no pub.dev via GitHub Actions com OIDC, sem token salvo.
- **Performance:** o pre-commit deve rodar em 1–2 s. Medir e reportar o tempo de cada check.

## Riscos conhecidos a verificar cedo

- **Windows:** `pub global activate` gera `stagelatch.bat`, e o hook roda no `sh` do Git for Windows, que pode não resolver `.bat`. Validar e tratar no hook gerado (por exemplo, com fallback para `dart pub global run stagelatch`).
- **API do analyzer:** muda entre versões maiores. Fixar o range e testar contra o Dart beta no CI.
- **Codegen:** respeitar projetos que **não** versionam arquivos gerados (`generated_files_committed: false`).