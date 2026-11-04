# ADR-001: Bộ pre-commit chuẩn cho repo Go/TypeScript (macOS + Linux)

**Status:** Proposed
**Date:** 2026-11-03
**Deciders:** Backend Leader, DevOps/Platform, đại diện team FE
**Phạm vi:** mọi repo Go/TS do team sở hữu; áp dụng trước cho 1–2 repo pilot

## Context

- Team làm việc trên macOS (Apple Silicon + Intel) và Linux; không có Windows.
- Stack chính: Go + TypeScript, Dockerfile, một ít Terraform/k8s manifest.
- Yêu cầu tối thiểu: **lint**, **trivy**, **gitleaks** chạy ở local trước khi code lên remote.
- Ràng buộc thực tế:
  - Hook chậm (> 10s) thì dev sẽ `--no-verify`; sau đó hook thành vô nghĩa.
  - Dev commit từ JetBrains (GUI) nhiều hơn từ terminal → PATH của process hook rất tối giản trên macOS.
  - Version tool lệch giữa máy dev / IDE / CI sinh ra "máy tôi chạy được".
  - Một số môi trường mạng nội bộ chặn registry lạ (ghcr.io, mirror.gcr.io) → trivy DB có thể không tải được.
- Local hook **không phải** chốt chặn bảo mật (bypass được bằng `--no-verify`); CI mới là chốt. Local hook là để rút ngắn vòng feedback.

## Decision

1. **Framework hook:** dùng `pre-commit` (pre-commit.com), cài 3 hook type: `pre-commit`, `commit-msg`, `pre-push`.
2. **Quản lý binary:** tool nặng/đa ngôn ngữ (gitleaks, trivy, golangci-lint, govulncheck, hadolint, shellcheck, actionlint) **không** để pre-commit tự build (`language: golang`) mà pin bằng **mise.toml** và gọi qua `language: script` + wrapper `scripts/hooks/with-tools.sh` (bổ sung PATH cho GUI). Tool nhẹ thuần Python (yamllint, typos, conventional-pre-commit, pre-commit-hooks) để pre-commit tự quản lý.
3. **Phân tầng theo thời gian chạy:**
   - `pre-commit` (< 10s): vệ sinh file, gitleaks (staged), golangci-lint `--new-from-rev=HEAD --fix`, eslint/prettier trên file stage, shellcheck, hadolint, yamllint, typos, sqlfluff (`*.sql`), terraform fmt + tflint (`*.tf`), **trivy misconfig** (chỉ khi IaC thay đổi).
   - `pre-push` (30–60s chấp nhận được): **trivy vuln** (lockfile), govulncheck, `tsc --noEmit`, **semgrep** (p/golang, p/typescript, p/dockerfile + rule riêng trong `.semgrep/`).
   - `commit-msg`: Conventional Commits.
4. **CI parity:** CI chạy `pre-commit run --all-files` + golangci-lint full + gitleaks full history. Local lint theo diff, CI lint toàn bộ.
5. **Hai tầng, cả hai đều chạy, global trước:** áp dụng global bằng `core.hooksPath` + dispatcher (`install.sh`), không dùng `pre-commit init-templatedir`. Thứ tự dùng là *cài kit → clone → commit*: repo không cần chứa file nào của kit.
   - Tầng 1 (global, bắt buộc — security floor): profile của kit (`full` mặc định; `minimal` = gitleaks + vệ sinh). Repo **không** bỏ được tầng này bằng cách sửa file trong repo; chỉ chỉnh được tool qua file config của tool ở root repo (`kit-run`: repo trước, kit mặc định sau).
   - Tầng 2 (repo, bổ sung): `.pre-commit-config.yaml` của repo nếu có — hook đặc thù (go test, generate-check, chặn `.env`…).
   - Tầng 1 fail → dừng. Repo nhúng bản standalone (marker `# precommit-kit-standalone`) thì tầng 1 hạ xuống `minimal` để không chạy trùng.
   - CI chạy đúng 2 tầng (checkout repo kit + `install.sh --no-mise`), để `--no-verify` không lọt.
   Xem sub-decision bên dưới.
6. **Tránh trùng chức năng:** trivy secret scanner tắt (gitleaks lo); `detect-private-key` của pre-commit-hooks không bật (gitleaks lo); gosec G101 vẫn giữ vì nó bắt theo ngữ cảnh code Go.

## Options Considered

### Option A: pre-commit framework + binary pin bằng mise (CHỌN)

| Dimension | Assessment |
| ----------- | ------------ |
| Complexity | Medium — thêm 1 dependency Python, 1 file mise.toml, 2 wrapper script |
| Cost | Thấp; cài 1 lần qua `bootstrap.sh` |
| Scalability | Cao — ~hàng trăm hook sẵn, `files`/`types` filter, `--all-files`, `autoupdate`, SKIP env |
| Team familiarity | Trung bình — phổ biến nhất trong ecosystem, dev Python/DevOps đều quen |

**Pros:** hệ sinh thái hook lớn nhất; filter file theo type rất gọn; chạy giống nhau ở CI (`pre-commit run --all-files`); gitleaks/golangci-lint/hadolint đều có manifest chính chủ; `SKIP=` và `--no-verify` có kiểm soát; cache env per-rev.
**Cons:** cần Python 3 (macOS có sẵn; Linux cần pipx hoặc mise); chạy tuần tự (không song song); hook `language: golang` build từ source rất chậm → phải né bằng cách dùng binary system (đây là lý do cần mise).

### Option B: lefthook (Go, single binary)

| Dimension | Assessment |
| ----------- | ------------ |
| Complexity | Low–Medium |
| Cost | Thấp |
| Scalability | Tốt — `parallel: true`, `{staged_files}`, `stage_fixed` |
| Team familiarity | Thấp–Trung bình |

**Pros:** 1 binary, không cần Python, chạy song song, config đơn giản, hợp team Go.
**Cons:** không có "hook registry" — tự quản lý cài đặt mọi tool (vẫn cần mise); filter type file bằng glob thủ công; ít sẵn các hook vệ sinh nhỏ (end-of-file, merge-conflict, large-file) phải tự viết; CI parity phải tự dựng.

### Option C: husky + lint-staged

| Dimension | Assessment |
| ----------- | ------------ |
| Complexity | Low cho repo JS thuần |
| Cost | Thấp |
| Scalability | Kém cho repo Go/IaC — mọi thứ phải chui qua npm script |
| Team familiarity | Cao với FE |

**Pros:** FE quen; `lint-staged` rất tốt cho eslint/prettier.
**Cons:** bắt repo Go phải có package.json; chạy tuần tự; không có cơ chế pin binary ngoài Node; không phù hợp monorepo Go-first.

### Option D: script `.git/hooks` tự viết + `core.hooksPath`

**Pros:** zero dependency.
**Cons:** tự duy trì mọi thứ (filter file, cache, bỏ qua hook, cross-platform sed/find); kinh nghiệm thực tế là sau 6 tháng không ai dám sửa.

### Sub-decision: binary do pre-commit build (`language: golang`) vs binary hệ thống

- `language: golang` (hook chính chủ của gitleaks/golangci-lint): pre-commit `go install` trong env riêng → lần đầu mất vài phút/máy, cần Go toolchain và GOPROXY mở, version golangci-lint trong IDE (JetBrains plugin) có thể khác → kết quả lint khác nhau.
- Binary hệ thống + mise.toml: 1 nguồn version cho IDE/hook/CI (`jdx/mise-action` đọc cùng file), cài song song nhanh, hoạt động offline sau lần đầu.
→ Chọn binary hệ thống. Chi phí: dev phải chạy `bootstrap.sh`; hook `with-tools.sh` báo lỗi rõ ràng nếu thiếu.

### Sub-decision: áp dụng global — `core.hooksPath` + dispatcher vs `init.templateDir`

| | `pre-commit init-templatedir` + `init.templateDir` | `core.hooksPath` global + dispatcher (CHỌN) |
| --- | --- | --- |
| Repo đã clone trước khi cài | **Không** có hook (template chỉ áp dụng khi clone/init) | Có ngay |
| Repo không có `.pre-commit-config.yaml` | Commit **fail** (trừ khi `PRE_COMMIT_ALLOW_NO_CONFIG=1`) | Chạy profile global (full/minimal) với config mặc định của kit |
| Hook cục bộ `.git/hooks/*` có sẵn | Giữ nguyên | Bị git bỏ qua → dispatcher phải tự chain (đã làm) |
| Repo đặt `core.hooksPath` local (husky) | Không ảnh hưởng | Ghi đè global → kit không chạy ở repo đó |
| `pre-commit install` trong repo | Bình thường | Bị từ chối → bootstrap phải nhận biết (đã làm) |
| Gỡ | Xoá template, nhưng hook đã copy vào từng repo vẫn còn | `git config --global --unset core.hooksPath` là sạch |

Giá trị chính của "global" là **toàn bộ kit chạy ở mọi repo ngay sau clone**, kể cả repo cũ/repo người khác, mà không phải commit file kit vào từng repo; `init.templateDir` không đạt được điều đó. Chi phí: dispatcher ~90 dòng bash phải chain đúng stdin (pre-push) và exit code; wrapper `kit-run` ~60 dòng để chọn config; hook do pre-commit quản lý env (yamllint, typos, sqlfluff, semgrep, markdownlint) phải override `entry` trong config để đi qua `kit-run` — pre-commit cho phép override mọi key của manifest trừ `id`/`language`.

Hệ quả của profile `full` toàn cục cần nói rõ: (1) hook **tự sửa file** (gofmt, prettier, sqlfluff fix, markdownlint --fix, end-of-file-fixer) sẽ chạy cả ở repo người khác/repo open-source; (2) `no-commit-to-branch main` áp cho mọi repo; (3) conventional commit áp cho mọi repo. Với repo không muốn vậy: `git config precommit-kit.profile minimal` (hoặc `off`) trong repo đó. Mặc định vẫn là `full` vì đó là yêu cầu của team và chi phí tắt theo repo là một lệnh.

Phát hiện khi kiểm chứng (2): hook `typos` chính chủ mặc định `--write-changes` — **tự sửa file**. Với text tiếng Việt nó sửa sai ("tham số" → "than số") và đã làm hỏng 5 file của chính kit trong lúc test. Kit override `args: [--force-exclude]` để typos chỉ báo; sửa thì chạy tay `typos -w`. Nguyên tắc rút ra: hook auto-fix chỉ được bật khi fix là deterministic (formatter), không bật cho tool "đoán" (spell check).

Phát hiện khi kiểm chứng (1): manifest upstream của hook `gitleaks-system` (gitleaks v8.30.1) **thiếu `pass_filenames: false`** → pre-commit nối tên file vào lệnh, gitleaks coi đó là source path và quét 0 byte, luôn Passed. Config của kit override `pass_filenames: false`; đáng gửi PR lên upstream.

### Sub-decision: repo config THAY global hay CỘNG với global

Bản đầu của dispatcher cho repo config thay thế global ("repo biết rõ nhất"). Đổi sang **cộng** vì mục tiêu là bảo mật: nếu repo config thay được global thì một PR sửa `.pre-commit-config.yaml` (hoặc một repo cũ có config sơ sài) là mất gitleaks/trivy trên máy dev — đúng chỗ cần chặn nhất. Chi phí: (1) thời gian = tổng hai tầng, nên tầng 2 phải là hook đặc thù chứ không lặp kit; (2) repo nhúng standalone bị chạy trùng → xử lý bằng marker hạ tầng 1 xuống `minimal`; (3) hai lần stash/unstash của pre-commit ở stage pre-commit — đã test, không lỗi.

### Sub-decision: nhận diện ngôn ngữ — per-file (pre-commit `identify`) + per-project (`kit-run --project`)

Không có bước "detect ngôn ngữ của repo" riêng; nhận diện ở hai mức:

- **Per-file**: pre-commit gắn type cho từng file stage (đuôi + shebang), hook filter bằng `types`/`types_or`/`files`. Đủ cho repo đơn ngôn ngữ; hook của ngôn ngữ vắng mặt tự Skipped, chi phí 0.
- **Per-project**: `kit-run --project <marker>` gom file theo thư mục gần nhất có `go.mod`/`package.json`/`tsconfig.json` và chạy tool *trong* thư mục đó, config theo `project > repo root > kit`. Cần vì golangci-lint/eslint/tsc hiểu "project" theo thư mục chứa marker chứ không theo file; chạy ở repo root sẽ sai ở monorepo. Đã test `backend/` Go + `frontend/` TS: golangci chạy trong `backend/`, prettier trong `frontend/`, file JS ở root không có `package.json` → bỏ qua.
- Giới hạn còn lại: (1) `sqlfluff` khi repo root không có `.sqlfluff` thì kit inject config mặc định, làm mất cơ chế tự tìm `.sqlfluff` lồng của sqlfluff — repo có nhiều dialect nên đặt `.sqlfluff` ở root; (2) marker là cố định trong config (`go.mod`, `package.json`, `tsconfig.json`); Bazel/Nx/Turborepo có cấu trúc khác cần thêm hook riêng ở tầng 2.

### Sub-decision: Java / .NET / Python

| | Lựa chọn | Lý do / trade-off |
|---|---|---|
| Java format | google-java-format **binary native** tự tải (không JDK), mặc định AOSP 4 space | Teams Java VN dùng IntelliJ 4 space; Google 2 space là mặc định của tool nhưng ít được chấp nhận. Có đường đổi về Google style |
| Java lint | checkstyle jar tự tải + `checkstyle.xml` của kit (google_checks chỉnh indent 4, bỏ Javadoc bắt buộc, line 120) | google_checks nguyên bản mâu thuẫn với AOSP format (đã vấp khi test) và Javadoc bắt buộc gây ồn. Không dùng mvn/gradle plugin vì hook > 10s |
| Java SAST/CVE | semgrep p/java; trivy pom.xml/gradle.lockfile | PMD/SpotBugs cần build classpath → CI |
| .NET format | `dotnet format` có sẵn SDK, chạy theo `*.sln,*.csproj` gần nhất, `--include` file stage | Không có tool format .NET nào nhẹ hơn; SDK phải có sẵn (mise plugin dotnet chưa đủ tin cậy để pin) |
| .NET CVE | `dotnet list package --vulnerable` (pre-push) + trivy khi có `packages.lock.json` | trivy không thấy NuGet nếu không có lockfile — phải thay đổi repo (`RestorePackagesWithLockFile`) |
| Python | ruff (check + format) qua hook chính chủ; semgrep p/python; trivy | Một tool thay flake8/isort/black, không cần cài gì thêm |
| Binary ngoài mise | `_fetch.sh`: tải từ GitHub releases, pin version, cache `~/.cache/precommit-kit` | mise registry không chắc có gjf/checkstyle; tải trực tiếp deterministic hơn. Chưa pin sha256 (để trống, điền khi phát hành) |

Chưa kiểm chứng: `dotnet format` trên SDK thật (môi trường test không có .NET); `kit-dotnet-vuln` parse output theo chuỗi "has the following vulnerable packages" — phụ thuộc wording của SDK, cần xác nhận trên SDK team dùng.

### Kiểm chứng đa nền tảng (04/11/2026)

`tests/container-smoke.sh` (17 case) chạy trong container từ rootfs chính thức: Alpine 3.21 (musl/apk), Ubuntu 22.04 (glibc/apt), Fedora 43 (glibc/dnf) — **17/17 cả ba**. Hai lỗi thật bắt được nhờ test này, sửa trong cùng ngày:

1. `markdownlint-cli` là `language: node` → pre-commit tải nguyên Node.js (nodeenv) về mỗi máy; mạng chặn `nodejs.org`/`unofficial-builds.nodejs.org` (Alpine) thì **vỡ toàn bộ stage pre-commit, kể cả gitleaks**. Thay bằng `rumdl` (Rust, wheel PyPI có bản musl, đọc `.markdownlint.yaml`). Nguyên tắc rút ra: global config không được có hook `language: node`/`golang`/`rust` (pre-commit phải tải toolchain), chỉ `python` (wheel) và `system`.
2. `kit-run` kiểm tra lệnh tồn tại (`npx`) *trước* `--if-exists node_modules/.bin/prettier` → máy không có Node vỡ ở mọi file `.md/.json/.yaml`. Đảo thứ tự.
Ngoài ra test phát hiện `.yamllint.yml` bị xóa nhầm khỏi kit trong quá trình phát triển (đếm file config). Chưa kiểm chứng: macOS (không có máy); bash 3.2 (chỉ quét tĩnh cú pháp + shellcheck); `mise install` thật (môi trường test chặn Adoptium/nodejs.org/go.dev).

## Trade-off Analysis

| Trade-off | Lựa chọn | Lý do |
| ----------- | ---------- | ------- |
| Tốc độ vs độ phủ ở pre-commit | Lint theo diff (`--new-from-rev=HEAD`), vuln scan dời sang pre-push | Hook > 10s sẽ bị bypass; CI mới là nơi quét full |
| Trivy ở local có đáng không | Có, nhưng tách misconfig (nhanh, không cần DB) khỏi vuln (cần DB ~70MB) | Misconfig Dockerfile/k8s là lỗi dev sửa ngay được; vuln lockfile ít đổi, chạy pre-push đủ |
| Python dependency | Chấp nhận | pre-commit là Python nhưng mise cài được, không đụng Python hệ thống; đổi lại ecosystem hook |
| Pin version chặt vs `latest` | Pin chặt trong mise.toml và `rev:` | Lint/secret rule đổi theo version → build lúc xanh lúc đỏ nếu không pin. Nâng version là 1 PR có chủ đích |
| Auto-fix trong hook (`--fix`, `--write`) | Bật | Hook fail lần 1 kèm file đã sửa, dev `git add` lại; đỡ hơn báo lỗi để sửa tay. Rủi ro: dev không đọc diff do tool sửa |
| Comment tiếng Việt vs `typos` | Giữ typos, whitelist từng từ | typos bắt được lỗi trong identifier/doc tiếng Anh; nếu false positive quá nhiều thì tắt typos cho `*.go` comment hoặc thống nhất comment tiếng Anh |

## Consequences

**Dễ hơn:**

- Secret, misconfig Dockerfile, lỗi lint cơ bản bị chặn trong < 10s, trước khi CI chạy 5–10 phút.
- Version tool đồng nhất IDE/hook/CI nhờ một `mise.toml`.
- Onboard dev mới: `./scripts/bootstrap.sh` xong.

**Khó hơn / chi phí:**

- Thêm 1 lớp phải bảo trì: `.pre-commit-config.yaml` + `mise.toml` (nâng version định kỳ, nên gắn Renovate/Dependabot cho `pre-commit` manager).
- Repo cũ bật hook lần đầu sẽ thấy nhiều lỗi khi CI chạy full golangci-lint → cần 1 PR "lint baseline" hoặc dùng `--new-from-rev` ở CI trong giai đoạn chuyển tiếp.
- Dev dùng Docker-only workflow (không cài tool trên host) phải dùng hook `*-docker` hoặc chạy trong devcontainer.

**Cần xem lại sau 1 quý:**

- Thời gian trung bình của pre-commit (đo bằng `PRE_COMMIT_COLOR=never pre-commit run -v`); nếu > 10s thì chuyển thêm hook sang pre-push hoặc cân nhắc lefthook (song song).
- Tỉ lệ dùng `--no-verify` (CI báo cáo commit fail hook nào).
- Số entry trong `.gitleaksignore` / `.trivyignore` (dấu hiệu rule quá ồn hoặc nợ bảo mật).

## Action Items

1. [ ] Chọn 1 repo Go + 1 repo TS làm pilot; copy kit vào, sửa `local-prefixes` trong `.golangci.yml`, module path trong `.gitleaks.toml`.
2. [ ] Chạy `make lint-all` trên repo pilot, tạo PR "chore: lint baseline" sửa/whitelist lỗi tồn đọng.
3. [ ] Bật workflow `.github/workflows/pre-commit.yml` (hoặc port sang GitLab CI) làm required check.
4. [ ] Thêm `mise.toml` + `.pre-commit-config.yaml` vào Renovate config (manager `pre-commit`, `mise`).
5. [ ] Viết hướng dẫn 1 trang cho dev: cài, SKIP, `.gitleaksignore`, cách xử lý khi hook sửa file.
6. [ ] Sau 1 tháng: đo thời gian hook, quyết định có giữ typos/markdownlint hay không; mở rộng ra các repo còn lại.
7. [ ] Semgrep: sau 1 tháng chạy, review finding của `p/golang`/`p/typescript`; rule nào ồn thì chuyển sang `.semgrep/` bản chỉnh sửa hoặc `--exclude-rule`. Viết thêm rule riêng theo lỗi hay gặp trong code review (mẫu: `.semgrep/go-sql-string-concat.yaml`).
8. [ ] Gửi PR upstream gitleaks: thêm `pass_filenames: false` cho hook `gitleaks-system`.
9. [ ] tflint: bật plugin cloud (`aws`/`google`/`azurerm`) trong `.tflint.hcl` theo provider thực tế; `terraform validate` để ở CI (cần `init`).
