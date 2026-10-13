# ConjoinedTwins 项目 Claude 规则

本项目的完整开发规则以 `AGENTS.md` 为准，Claude Code 与其他 Agent 共用同一份规则，避免两处内容漂移。修改规则时只改 `AGENTS.md`，本文件仅保留导入与 Claude 专属补充。

@AGENTS.md

## Claude Code 补充

- 开始开发任务前先确认当前分支：若位于 `main` 或 `dev`，先从最新 `dev` 创建任务分支（命名见 AGENTS.md「Git 分支与提交规则」），再修改文件。
- 合并、推送、删除分支等不可逆 Git 操作必须先在对话中取得用户明确同意，单次同意不延续到后续操作。
- 提交信息末尾按会话提供的署名要求追加 Co-Authored-By 行。
