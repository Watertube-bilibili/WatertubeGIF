---
name: recent-gif
description: 获取水管 GIF 最近一次成功生成且仍然存在的 GIF，返回成品信息与只读文件 URI
---

## 触发场景

当用户明确希望获取、查看或发送最近生成的 GIF 时调用。典型话术：

- “打开我刚刚生成的 GIF”
- “把最近转换的 GIF 给我”
- “看看水管 GIF 最后一次的结果”
- “获取最新的 GIF 成品”

不调用的情况：

- 用户要求重新转换、裁剪或修改参数，本 Skill 只读取已有结果。
- 用户要求删除历史或文件，本 Skill 不执行写入和删除操作。
- 用户没有明确提到最近生成的 GIF。

### 场景 1：获取最近生成的 GIF（getRecentGif）

#### 执行参数

exec-cli(command: ohos-arkTSScript --skillName 'recent-gif' --scriptPath 'scripts/RecentGifSkill.ets' --functionName 'getRecentGif' --args '{}')

```json
{
  "args": {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  }
}
```

#### 执行返回值

成功：

```json
{
  "type": "result",
  "status": "success",
  "data": {
    "title": "最近生成的 GIF",
    "width": 720,
    "height": 1280,
    "frames": 120,
    "size": 1048576,
    "createdAt": 1785000000000
  }
}
```

没有可用成品：

```json
{
  "type": "result",
  "status": "failed",
  "errCode": "ERR_NOT_FOUND",
  "errMsg": "还没有可用的 GIF",
  "suggestion": "请先在水管 GIF 中完成一次转换"
}
```

内部错误：

```json
{
  "type": "result",
  "status": "failed",
  "errCode": "ERR_INTERNAL",
  "errMsg": "读取最近 GIF 失败",
  "suggestion": "请稍后再试"
}
```

```json
{
  "type": "object",
  "required": ["type", "status"],
  "properties": {
    "type": { "type": "string", "const": "result" },
    "status": { "type": "string", "enum": ["success", "failed"] },
    "data": { "type": "object" },
    "errCode": { "type": "string", "enum": ["ERR_NOT_FOUND", "ERR_INTERNAL"] },
    "errMsg": { "type": "string", "minLength": 1 },
    "suggestion": { "type": "string", "minLength": 1 }
  },
  "oneOf": [
    {
      "properties": { "status": { "const": "success" } },
      "required": ["data"]
    },
    {
      "properties": { "status": { "const": "failed" } },
      "required": ["errCode", "errMsg", "suggestion"]
    }
  ]
}
```
