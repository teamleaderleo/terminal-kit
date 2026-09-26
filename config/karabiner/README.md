# Karabiner

`terminal-kit.json` is one rule, active only while cmux is frontmost: Cmd-Shift-] and Cmd-Shift-[ send Ctrl-Tab and Ctrl-Shift-Tab (next / previous surface), like browser tabs. cmux allows one shortcut per action, so this is how the second binding gets in.

`tk apply` copies the rule into Karabiner's assets and adds or refreshes it in the selected profile. Nothing else in your Karabiner config is touched.
