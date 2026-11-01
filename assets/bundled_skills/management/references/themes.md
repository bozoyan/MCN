# 应用界面主题管理

用于用户要求修改应用界面配色，不用于小说主题或立意。主题作用于整个应用，桌面和移动端共用。暂不支持字体、间距、圆角、布局、背景图片或语义状态色的修改。

使用 `Run` 的 `themes` 命令。先 list / read 获取真实 ID、颜色和版本；不要猜测 ID。内置主题 ID 为 `builtin:<name>`，自定义主题 ID 由 create 返回。名称不作为地址。

用户明确要求更换配色时可以保存并应用；只要建议时不要写入。create 默认不应用。修改正在使用的自定义主题会立即生效。删除只在用户明确要求时执行。

## 列表与详情

```text
Run {"command":"themes","subcommand":"list","options":{}}
Run {"command":"themes","subcommand":"read","options":{"id":"builtin:reveric"}}
```

list 返回 entries、activeId、themeMode。read 返回主题信息、最终 lightColors / darkColors、editableColors；自定义主题还返回 baseTheme、lightOverrides、darkOverrides、revision。

## 创建

```text
Run {"command":"themes","subcommand":"create","options":{"name":"森林书房","baseTheme":"reveric","lightOverrides":{"accent":"#245C42","onAccent":"#FFFFFF"},"darkOverrides":{"accent":"#A4CBA6","onAccent":"#172118"}}}
```

- name 必填，1–100 字符。baseTheme 必填，只能是内置主题名称：reveric、classic、ivory。这里使用名称，不带 `builtin:` 前缀；不能继承自定义主题。
- lightOverrides / darkOverrides 可省略；只提交需要修改的颜色，其余继承 baseTheme 的对应明暗配色。内置配色后续更新会影响继承的颜色。
- 颜色为不透明 `#RRGGBB`。editableColors 是允许修改的字段；成功、错误、警告和增删状态色保持内置值。
- 背景使用 canvas / surface / surfaceDim / surfaceContainer / surfaceContainerHigh；文字使用 textPrimary / textSecondary / textMuted / textSubtle / textTertiary；主色使用 accent 及其前景 onAccent，其他装饰强调色使用 accentWarm / accentAmber；边框使用 border / borderSubtle / borderInput / blockquoteBorder；交互背景使用 selected / hover。
- 优先成对调整前景与背景。改动触及的正文/背景以及 onAccent/accent 对比度不得低于 4.5；失败会指出颜色对，需要修正后再提交。

从自定义主题复制时先 read，再把它的 baseTheme 和两套 overrides 提交给 create。

## 更新与清除覆盖

```text
Run {"command":"themes","subcommand":"update","options":{"id":"<read 返回的 id>","revision":1,"lightOverrides":{"accent":"#28543D","border":null}}}
```

id、revision 必填。可改 name、baseTheme、lightOverrides、darkOverrides，至少提供一个修改字段。颜色对象按字段合并；null 表示清除该颜色覆盖，恢复继承。省略字段表示保持原值。更换 baseTheme 保留现有覆盖，需要恢复继承的字段显式设为 null。

版本冲突时重新 read，结合用户最新要求修改，不要盲目重复提交。写入成功返回新的 revision。

## 应用

```text
Run {"command":"themes","subcommand":"apply","options":{"id":"<create 返回的 id>","themeMode":"system"}}
Run {"command":"themes","subcommand":"apply","options":{"id":"builtin:reveric"}}
```

id 必填；themeMode 可选 light / dark / system，省略则保持原有模式。恢复内置主题使用 apply，不必删除自定义主题。用户未要求改变明暗模式时保持原值。

## 删除

```text
Run {"command":"themes","subcommand":"delete","options":{"id":"<read 返回的 id>","revision":1}}
```

只允许删除自定义主题，id、revision 必填。删除当前主题时自动切回它的 baseTheme，保持明暗模式。

操作成功后简短回报主题名称及是否已经应用。失败时报告原因，不得将只生成了配色方案描述为已经保存或应用。
