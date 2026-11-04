# precommit-kit — Go/TypeScript, macOS + Linux

Bộ git hook chuẩn: **lint** (golangci-lint v2, eslint/prettier), **gitleaks**, **trivy**, cùng các hook vệ sinh/IaC.
Quyết định thiết kế và trade-off: [docs/ADR-001-pre-commit-toolchain.md](docs/ADR-001-pre-commit-toolchain.md).

## Cài đặt

### A. Global cho cả máy (khuyến nghị) — `install.sh`

Thứ tự: **cài kit → clone repo → commit**. Repo không cần chứa file nào của kit.

```bash
git clone <repo-kit> ~/precommit-kit && cd ~/precommit-kit
./install.sh              # mise -> toàn bộ tool trong mise.toml (global) -> core.hooksPath, profile "full"
./install.sh --minimal    # chỉ pre-commit + gitleaks; profile "minimal" (gitleaks + vệ sinh)
./install.sh --status     # kiểm tra
./install.sh --uninstall  # gỡ core.hooksPath + ~/.config/precommit-kit (không gỡ tool)

git clone <repo-team> && cd <repo-team>
git commit ...            # toàn bộ kit chạy
```

Cài vào `~/.config/precommit-kit/`:

| | |
| --- | --- |
| `hooks/dispatch.sh` | `core.hooksPath` global trỏ vào đây; mọi tên hook git symlink về nó |
| `pre-commit-config.full.yaml` / `.minimal.yaml` | profile global; chọn bằng `git config [--global] precommit-kit.profile <full / minimal / off>` |
| `bin/kit-run`, `kit-trivy-scan`, `kit-go-mod-tidy`, `kit-tflint` | wrapper; dispatcher đưa `bin/` vào PATH |
| `config/` | config mặc định của từng tool (`.golangci.yml`, `.gitleaks.toml`, `.yamllint.yml`, `.sqlfluff`, `.tflint.hcl`, `.semgrep/`…) |

Hai tầng, **cả hai đều chạy**, theo thứ tự:

| Tầng | Config | Vai trò | Ai kiểm soát |
|------|--------|---------|--------------|
| 1 · global | `~/.config/precommit-kit/pre-commit-config.<profile>.yaml` | security floor: gitleaks, trivy, semgrep, lint… — **luôn chạy**, repo không bỏ được bằng cách sửa file trong repo | Platform/Security (qua repo kit) |
| 2 · repo | `.pre-commit-config.yaml` của repo (nếu có) | hook đặc thù: go test, generate-check, chặn `.env`, rule riêng… mẫu: `templates/repo/.pre-commit-config.yaml` | Team của repo |

Tầng 1 fail → dừng, không chạy tầng 2. Muốn **chỉnh** tool của tầng 1 cho một repo: đặt `.golangci.yml` / `.gitleaks.toml` / `.yamllint.yml` / `.sqlfluff` / `.tflint.hcl` / `.semgrep/` ở root repo — `kit-run` ưu tiên file của repo, không thì dùng mặc định của kit. Hook cục bộ `.git/hooks/*` (husky cũ, lefthook) chạy trước cả hai tầng.

Repo nhúng nguyên kit bằng bản standalone (file `.pre-commit-config.yaml` ở root kit, có dòng `# precommit-kit-standalone`) thì tầng 1 tự hạ xuống `minimal` để không chạy trùng 25 hook; `PRECOMMIT_KIT_NO_DEDUP=1` nếu muốn chạy đủ.

## Ngôn ngữ được hỗ trợ

| Ngôn ngữ | Format / lint | SAST | CVE dependency | Cần gì trên máy |
|---|---|---|---|---|
| Go | golangci-lint v2 (+gosec), gofmt/goimports/gofumpt, go mod tidy | semgrep p/golang | trivy (go.sum), govulncheck | go (mise) |
| TypeScript / JavaScript | eslint, prettier (hoặc biome), tsc | semgrep p/typescript | trivy (lockfile) | node (mise) + tool trong `node_modules` của repo |
| Java | google-java-format (binary native, tự tải), checkstyle (jar, tự tải; config kit = google_checks chỉnh 4 space) | semgrep p/java | trivy (pom.xml, gradle.lockfile) | java 21 (mise) cho checkstyle |
| C# / .NET | `dotnet format` (whitespace + style + analyzers theo `.editorconfig`) | semgrep p/csharp | `dotnet list package --vulnerable` (pre-push); trivy nếu bật `packages.lock.json` | .NET SDK (team tự cài) |
| Python | ruff check + ruff format | semgrep p/python | trivy (requirements/poetry/uv/Pipfile) | không (ruff qua pre-commit) |
| SQL | sqlfluff | — | — | không |
| Shell | shellcheck | semgrep (bash trong p/default nếu bật) | — | shellcheck (mise) |
| Dockerfile | hadolint | semgrep p/dockerfile, trivy misconfig | — | hadolint (mise) |
| Terraform | terraform fmt, tflint | trivy misconfig | — | terraform, tflint (mise) |
| YAML / Markdown / JSON / TOML / GitHub Actions | yamllint, rumdl (markdown, đọc `.markdownlint.yaml`), check-*, actionlint | — | — | không |
| Mọi ngôn ngữ | typos, vệ sinh file | gitleaks | trivy fs quét mọi ecosystem nó biết (Rust, Ruby, PHP, Dart, Elixir, Swift, conan…) | — |

Chưa có lint riêng (chỉ có gitleaks + trivy CVE + semgrep nếu thêm ruleset): Kotlin (ktlint), Rust (rustfmt/clippy), PHP, Ruby, Swift, C/C++, Protobuf (buf). Thêm = 1 block hook trong `global/pre-commit-config.full.yaml`.

### Java — chi tiết

- Style mặc định: AOSP (4 space, line 120). Đổi sang Google (2 space): file `.java-format-style` nội dung `google` **và** `checkstyle.xml` của repo (trỏ `/google_checks.xml`). Hai tool phải cùng style, không thì format xong checkstyle vẫn fail.
- checkstyle: `checkstyle.xml` hoặc `config/checkstyle/checkstyle.xml` ở root repo được ưu tiên; `checkstyle-suppressions.xml` ở root tự được đọc. Không bắt buộc Javadoc trong config mặc định.
- Binary/jar tải 1 lần vào `~/.cache/precommit-kit/` từ GitHub releases (pin version trong script `kit-java-format` / `kit-checkstyle`). Mạng chặn github.com: tải tay rồi đặt vào đó.
- Không gọi mvn/gradle trong hook (quá chậm). spotless/pmd/spotbugs để ở CI hoặc tầng 2 pre-push.

### .NET — chi tiết

- `dotnet format` chạy trong thư mục có `*.sln` gần nhất (không có thì `*.csproj`), chỉ `--include` file đã stage, tự sửa → re-add. Lần đầu cần restore (có mạng NuGet); không truyền `--no-restore`.
- Rule style/analyzer lấy từ `.editorconfig` của repo (`dotnet format` không có cờ config ngoài). Kit không inject mặc định — repo .NET nên có `.editorconfig` (`dotnet new editorconfig`).
- CVE: bật `<RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>` trong `Directory.Build.props` để trivy quét được NuGet; `kit-dotnet-vuln` (pre-push) dùng NuGet audit, cần mạng.
- Chưa test trên SDK thật trong môi trường này (chỉ test logic chọn project bằng `dotnet` giả) — cần chạy thử trên máy có .NET SDK trước khi phát hành.

## Nhận diện ngôn ngữ

- **Per-file:** pre-commit gắn type cho từng file đã stage (đuôi file + shebang, thư viện `identify`); hook khai báo `types: [go]`, `types_or: [ts, tsx]`, `[dockerfile]`, `[terraform]`, `[sql]`, `[shell]`… Không có file khớp → `Skipped`. Repo chỉ có Go thì eslint/tsc/sqlfluff/tflint không bao giờ chạy.
- **Per-project (monorepo):** `kit-run --project <marker>` gom file theo thư mục gần nhất có `go.mod` / `package.json` / `tsconfig.json`, chạy tool **trong** từng thư mục đó, config tìm theo `project > repo root > kit`. `backend/` Go + `frontend/` TS trong một repo chạy đúng tool đúng chỗ.
- **Toolchain của repo:** eslint/prettier/biome/tsc chỉ chạy khi có trong `node_modules/.bin` của project hoặc root (workspace hoist); không có → bỏ qua, không lỗi.
- **Luôn chạy bất kể ngôn ngữ:** gitleaks, trivy vuln (pre-push), vệ sinh file, conventional commit.

Tắt: `git config precommit-kit.disable true` (1 repo), `PRECOMMIT_KIT_DISABLE=1` (1 lần), `--no-verify` (cả git).

Giới hạn: repo đặt `core.hooksPath` ở mức **local** (husky ≥ 5 làm vậy) sẽ ghi đè global → kit không chạy ở repo đó; `install.sh --status` chạy trong repo sẽ cảnh báo. Muốn có thì thêm `pre-commit run` vào `.husky/pre-commit`.

### B. Tầng 2 trong repo

- Chỉ cần hook bổ sung (máy dev đã cài A): copy `templates/repo/.pre-commit-config.yaml` vào root repo, sửa theo nhu cầu. Không cần bootstrap.
- Repo cần chạy được ở máy **chưa** cài A (hoặc muốn kit đi theo repo): copy toàn bộ kit vào root repo (bản standalone, giữ nguyên dotfile) rồi:

```bash
./scripts/bootstrap.sh          # cài mise -> tool theo mise.toml -> pre-commit install (hoặc chỉ warm env nếu đã có global)
./scripts/bootstrap.sh --check  # chỉ kiểm tra
```

Nếu đã cài A, bootstrap tự nhận ra và không gọi `pre-commit install` (pre-commit từ chối cài khi `core.hooksPath` được đặt).

Sau đó thêm vào shell rc (script sẽ nhắc): `eval "$(mise activate zsh)"`.

Thử ngay: `pre-commit run --all-files`

## Cấu trúc

| File | Vai trò |
| ------ | --------- |
| `install.sh` | Cài global: mise + tool, `core.hooksPath` → dispatcher, wrapper, config mặc định |
| `global/hooks/dispatch.sh` | Dispatcher: chain hook cục bộ → pre-commit với config repo hoặc profile global |
| `global/pre-commit-config.full.yaml` | Profile full: toàn bộ kit, dùng `kit-run` để lấy config mặc định |
| `global/pre-commit-config.minimal.yaml` | Profile minimal: gitleaks + vệ sinh |
| `scripts/hooks/kit-run` | Wrapper chạy tool: config `project > repo > kit` (`{cfg:--config}`), `--project go.mod\|package.json` cho monorepo, `--if-exists` bỏ qua tool không có. install.sh copy vào `~/.config/precommit-kit/bin` |
| `.pre-commit-config.yaml` | Định nghĩa hook, 3 stage: pre-commit / commit-msg / pre-push |
| `mise.toml` | Pin version mọi binary (go, node, pre-commit, gitleaks, trivy, golangci-lint, hadolint, shellcheck, actionlint, govulncheck) |
| `scripts/bootstrap.sh` | Cài toolchain + hook, idempotent |
| `scripts/hooks/trivy-scan.sh` | `misconfig` (pre-commit, nhanh) và `vuln` (pre-push, cần DB) |
| `scripts/hooks/go-mod-tidy.sh` | `go mod tidy` cho mọi module, fail nếu go.mod/go.sum đổi |
| `.gitleaks.toml` / `.gitleaksignore` | Rule + allowlist secret |
| `.golangci.yml` | golangci-lint **v2** (standard + gosec, revive, gocritic…; formatter gofmt/goimports/gofumpt) |
| `.trivyignore` | CVE / check ID được chấp nhận, kèm lý do |
| `.hadolint.yaml`, `.yamllint.yml`, `.typos.toml`, `.markdownlint.yaml` (rumdl đọc) | Config các linter phụ |
| `.sqlfluff` | sqlfluff: dialect (mặc định postgres), templater raw, style rule |
| `.tflint.hcl`, `scripts/hooks/tflint.sh` | tflint preset recommended; tự `--init` khi khai báo plugin cloud |
| `.semgrep/` | Rule semgrep riêng của team + test case (`semgrep test .semgrep/`); ruleset `p/golang`, `p/typescript`, `p/dockerfile` tải từ registry |
| `templates/repo/.pre-commit-config.yaml` | Mẫu tầng 2: hook đặc thù của repo (go test, generate-check, chặn `.env`) |
| `checkstyle.xml` | checkstyle mặc định (google_checks chỉnh 4 space, bỏ Javadoc bắt buộc, line 120) |
| `scripts/hooks/kit-java-format`, `kit-checkstyle`, `kit-dotnet-vuln` | Hook Java/.NET; `_fetch.sh` tải binary/jar pin version vào cache |
| `tests/container-smoke.sh` | 17 case end-to-end trên máy/container sạch; `tests/run-matrix.sh` chạy trên nhiều distro bằng Docker |
| `.github/workflows/pre-commit.yml` | CI chạy cả 2 tầng trên toàn bộ file + gitleaks full history (checkout repo kit, `install.sh --no-mise`) |
| `Makefile` | `make setup / lint / lint-all / security / security-full / fmt / hooks-update` |

## Các việc phải sửa khi áp vào repo thật

1. `.golangci.yml` → `formatters.settings.goimports.local-prefixes`: module path tổ chức.
2. `.gitleaks.toml` → rule `internal-api-token` (xoá hoặc sửa regex theo token nội bộ).
3. `.pre-commit-config.yaml`:
   - Repo dùng Biome: bỏ 2 hook `eslint`/`prettier`, mở comment hook `biome`.
   - Không có `tsconfig.json` ở root: sửa `-p` của hook `tsc` hoặc xoá.
   - Không dùng GitHub Actions: xoá hook `actionlint`, port workflow sang GitLab CI.
4. `mise.toml` → bỏ `go`/`node` nếu team quản lý runtime cách khác; bỏ `terraform`/`tflint` nếu không có IaC (hook tự skip khi không có `*.tf`, nhưng bootstrap sẽ báo thiếu).
5. `.sqlfluff` → `dialect` đúng DB (postgres/mysql/...). Hook chỉ chạy trên `*.sql`.
6. Semgrep: ruleset `p/*` cần mạng tới semgrep.dev mỗi lần chạy; mạng nội bộ chặn thì sửa args chỉ còn `--config=.semgrep/`. Dùng OpenTofu: đổi `terraform` -> `tofu` trong hook `terraform-fmt` và `mise.toml`.

## Thao tác hằng ngày

```bash
git commit -m "feat(x): ..."        # hook chạy tự động; nếu tool tự sửa file -> git add lại rồi commit tiếp
SKIP=trivy-vuln git push            # bỏ qua 1 hook có chủ đích
git commit --no-verify              # bỏ qua tất cả — CI vẫn chặn
pre-commit run --all-files          # như CI
pre-commit run --hook-stage pre-push --all-files
TRIVY_OFFLINE=1 git push            # mạng chặn registry: dùng DB đã cache
pre-commit autoupdate               # nâng rev hook do pre-commit quản lý (tool system: sửa mise.toml)
```

## Xử lý finding

- **gitleaks false positive:** thêm fingerprint (gitleaks in ra) vào `.gitleaksignore` kèm lý do, hoặc `// gitleaks:allow` ở cuối dòng. Secret thật đã commit: **rotate trước**, xoá khỏi history sau.
- **trivy:** CVE không ảnh hưởng → `.trivyignore` kèm ngày review. Misconfig Dockerfile: sửa (thêm `USER`, `--no-install-recommends`…), không ignore.
- **golangci-lint:** `//nolint:gosec // lý do` — bắt buộc có lý do (revive/nolintlint sẽ bắt nếu bật).
- **semgrep:** `// nosemgrep: <rule-id>` trên dòng đó, kèm lý do ở comment kế bên.
- **sqlfluff:** `-- noqa: RF04` cuối dòng; **tflint:** `# tflint-ignore: terraform_unused_declarations`.

## Hệ điều hành được hỗ trợ

| Nền tảng | Trạng thái | Ghi chú |
|---|---|---|
| macOS Apple Silicon / Intel | hỗ trợ | cần Command Line Tools (`xcode-select --install`); Homebrew không bắt buộc (mise có installer riêng) |
| Linux glibc x64 / arm64 (Ubuntu, Debian, Fedora, RHEL, Arch…) | hỗ trợ | `install.sh` kiểm tra `git curl python3` và in đúng lệnh cài theo apt/dnf/yum/pacman/zypper |
| WSL2 | hỗ trợ như Linux | repo phải nằm trong filesystem Linux (`~/…`), không phải `/mnt/c` |
| Alpine / musl | hỗ trợ một phần | google-java-format tự chuyển sang jar (cần java); wheel Python của semgrep có thể không có bản musl |
| Windows native (Git Bash / PowerShell) | **không** | script bash + symlink hook; dùng WSL2 |

Kết quả test 04/11/2026 (`tests/container-smoke.sh`, 17 case: platform, prereq message, install/uninstall, gitleaks, golangci-lint, conventional commit, hook Python/Rust wheel, 2 tầng): **Alpine 3.21 (musl) 17/17, Ubuntu 22.04 17/17, Fedora 43 17/17**. Chạy lại: `tests/run-matrix.sh` (cần Docker). macOS chưa chạy được trong môi trường test; script đã quét tĩnh không dùng cú pháp bash ≥ 4 và shellcheck sạch.

Nhận diện nằm ở `scripts/hooks/_platform.sh` (`KIT_OS`, `KIT_ARCH`, `KIT_LIBC`, `KIT_PKG`, `KIT_WSL`); mise tự chọn binary theo OS/arch cho từng tool.

## Ghi chú macOS vs Linux

- macOS FS case-insensitive → hook `check-case-conflict` chặn file chỉ khác hoa/thường (Linux CI sẽ vỡ).
- Script hook viết cho bash 3.2 (macOS mặc định), không dùng `sed -i ''`/GNU-only flag; `find -print0` dùng được cả BSD/GNU.
- Apple Silicon: mise tải đúng arch; không dùng Rosetta.
- Trivy cache: `~/Library/Caches/trivy` (mac) / `~/.cache/trivy` (linux). Lần đầu tải DB ~70MB; bootstrap làm nóng sẵn.
