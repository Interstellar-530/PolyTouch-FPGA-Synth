# 环境修复记录：Codex 沙箱与 GitHub 代理（2026-10-10）

## 症状

本轮早些时候所有免提权的 `exec` 调用都返回：

```
Failed to create unified exec process: helper_unknown_error: setup refresh had errors
```

同一时间 `apply_patch` 也报 `fs sandbox helper failed`。只有走审批（提权、绕过沙箱）的命令能执行，构建和烧录是靠这条路完成的。

另外 `git push` 连续两次失败，一次 `Recv failure: Connection was reset`，一次 `Failed to connect to github.com port 443`。

## 根因一：`.git` 的属主被改成了沙箱账户

`C:\Users\ROG\.codex\.sandbox\sandbox.2026-10-10.log` 里 60 次重复同一条错误：

```
deny ACE failed on E:\Working Space\FPGA\.git: SetNamedSecurityInfoW failed for E:\Working Space\FPGA\.git: 5
setup refresh completed with errors: [...]
setup error: setup refresh had errors
```

错误码 5 是拒绝访问。Codex 的 Windows 沙箱每次执行命令前都要给 `.git` 加一条 deny ACE，防止沙箱内的进程改写仓库元数据；这一步需要对象的所有者权限或 WRITE_DAC 权限。

检查发现 `E:\Working Space\FPGA\.git` 的属主是 `十一的电脑\CodexSandboxOffline`，不是当前用户 `十一的电脑\ROG`。当前进程运行在 Medium 完整性级别（未提权），既不是属主，ACL 里也只有 Modify 而没有 ChangePermissions，所以改不了 DACL，沙箱 setup 直接失败。历史日志显示这个错误最早出现在 2026-10-08，10-07 之前没有。

同一批被改成沙箱属主的还有工作区里的 `archive`、`docs`、`output`、`tmp`、`.gitignore`、`AGENTS.md`、`CLEANUP_REPORT.md`、`FPGA-Instrument.code-workspace` 和 `电子乐器项目规划.md`，但沙箱只对 `.git` 做硬化，所以只有它导致了失败。

顺便解释了一个老现象：`.git` 属主不是当前用户，git 会报 dubious ownership，所以之前所有 git 命令都要带 `-c safe.directory=...`。

### 处置

当前用户没有 SeTakeOwnershipPrivilege，`takeown` 和 `icacls /setowner` 都失败，所以改用重建法：把 `.git` 复制成一份由当前用户创建的新目录（新建对象属主自动是创建者），再替换原目录。

```powershell
robocopy 'E:\Working Space\FPGA\.git' 'E:\Working Space\FPGA\.git_rogupper' /E /COPY:DAT /DCOPY:DAT /R:1 /W:1
[System.IO.Directory]::Move('E:\Working Space\FPGA\.git', 'E:\Working Space\FPGA\.git_owner_bak2_20261010')
[System.IO.Directory]::Move('E:\Working Space\FPGA\.git_rogupper', 'E:\Working Space\FPGA\.git')
```

注意两个坑。第一，PowerShell 的 `Move-Item` 对隐藏目录会报 “insufficient access rights”，即使实际能移动；这里改用 `[System.IO.Directory]::Move` 就没有问题。第二，第一次尝试时 `Move-Item` 报错但已经复制出一份完整副本，随后的第二次移动把 `/.git_rogupper` 挪进了仍然存在的旧 `.git` 里，导致仓库一度不可用；后来用两份完整副本互相比对确认内容一致后才恢复，没有丢数据。

### 验证

- `.git` 属主变回 `十一的电脑\ROG`，200 个文件，`HEAD` 为 `ref: refs/heads/main`。
- 不带 `-c safe.directory` 也能执行 `git status` 和 `git log`。
- 沙箱 setup 日志变成 `processed 3 write roots (read roots delegated); errors=[]`，今天的 deny ACE 失败次数停在修复前的 60 次。
- 免提权的 `exec` 恢复正常：工作区内可写可删，工作区外写入被拒绝，说明沙箱生效且隔离正常。
- `git fsck` 无输出，`HEAD` 与 `origin/main` 都是 `b9f558f`。

## 根因二：git 没有走本机代理

本机在跑 Clash Verge，mihomo 监听 `127.0.0.1:7897`，系统 WinINET 代理已开启指向它。git for Windows 不使用 WinINET 设置，也不会自动继承，所以它直连 GitHub：实测直连 `https://github.com` 超时（http_code 000，12 秒），经代理返回 200。

### 处置

只给 GitHub 配置代理，不动全局 `http.proxy`，这样代理软件关闭时其他仓库不受影响：

```powershell
git config --global http.https://github.com.proxy http://127.0.0.1:7897
```

配置后 `git push origin main` 成功，远端从 `e9d6c02` 前进到 `b9f558f`。

`C:\Users\ROG\.gitconfig` 里原先有两条 `safe.directory`，现在 `.git` 属主已修正，`E:/Working Space/FPGA` 那条可以删掉；`E:/Working Space/CNN_v1.0/github_backup` 那条说明另一个仓库也有同样的属主问题，需要用同样的方法处理。

## 沙箱内的网络仍然不可用

当前线程的沙箱策略是 `{"type":"workspaceWrite","writableRoots":[],"networkAccess":false,...}`，实测:

| 位置 | 命令 | 结果 |
| --- | --- | --- |
| 沙箱内 | `curl -x http://127.0.0.1:7897 https://api.github.com/rate_limit` | 000 |
| 提权 | 同上 | 200 |
| 沙箱内 | `curl https://www.baidu.com` | 000，`connect ... failed: Bad access` |
| 沙箱内 | `TcpClient.Connect('127.0.0.1',7897)` | 成功 |

也就是说沙箱允许连回环端口，但出站 TCP 被过滤，schannel 也拿不到凭证。需要在沙箱内联网时，可以在 `C:\Users\ROG\.codex\config.toml` 增加：

```toml
[sandbox_workspace_write]
network_access = true
```

这个键在 codex.exe 里的结构是 `SandboxWorkspaceWrite { writable_roots, network_access, exclude_tmpdir_env_var, exclude_slash_tmp }`，改完需要重启 Codex 才生效。它会削弱沙箱隔离，因此本轮没有默认打开；网络类命令继续走审批即可。

## 遗留项

1. `E:\Working Space\FPGA\.git_owner_bak2_20261010` 是切换过程留下的重复副本，约 8.9 MB。里面的对象文件属主仍是 `CodexSandboxOffline`，未提权删不掉，已临时写进 `.git/info/exclude` 以免污染 `git status`。清理方式是在**管理员** PowerShell 里执行：

   ```powershell
   takeown /f "E:\Working Space\FPGA\.git_owner_bak2_20261010" /r /d y
   Remove-Item -LiteralPath "E:\Working Space\FPGA\.git_owner_bak2_20261010" -Recurse -Force
   ```

2. 工作区里 `archive`、`docs`、`output`、`tmp`、`.gitignore`、`AGENTS.md` 等条目的属主仍是 `CodexSandboxOffline`。目前不影响沙箱运行，若要一并纠正，在管理员 PowerShell 里执行 `takeown /f "E:\Working Space\FPGA" /r /d y`。

3. 每次沙箱启动都会出现一条非致命警告：`hide users: failed to hide current user profile dir (C:\Users\Default): SetFileAttributesW failed ... 5`。它来自隐藏其他用户目录的加固步骤，需要管理员权限，实测不影响命令执行，历史上也一直存在。

4. 另一台/另一个仓库 `E:\Working Space\CNN_v1.0\github_backup` 同样被写进了 `safe.directory`，很可能有相同的属主问题。

## 回退方式

- 取消 GitHub 代理：`git config --global --unset http.https://github.com.proxy`
- 若将来必须恢复旧 `.git`：旧副本在 `.git_owner_bak2_20261010\.git_rogupper`，内容与本轮生效的 `.git` 同源；因为远端已经是 `b9f558f`，更稳妥的做法是重新 `git clone` 到临时目录后再替换 `.git`。
