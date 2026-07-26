# terminal-kit: restrained command-line syntax colours.

# Valid commands get a muted sage tint; invalid or unresolved tokens get a
# subdued salmon tint. Everything else stays close to the indigo-grey theme.
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[default]='fg=#D8DBE8'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#B77F79'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#9AA9D8'
ZSH_HIGHLIGHT_STYLES[command]='fg=#A9C1A5'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#AFC7AA'
ZSH_HIGHLIGHT_STYLES[hashed-command]='fg=#A9C1A5'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#A9C1A5'
ZSH_HIGHLIGHT_STYLES[function]='fg=#A9C1A5'
ZSH_HIGHLIGHT_STYLES[alias]='fg=#A9C1A5'
ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=#A9C1A5'
ZSH_HIGHLIGHT_STYLES[global-alias]='fg=#A9C1A5'
ZSH_HIGHLIGHT_STYLES[path]='fg=#AEB8D7'
ZSH_HIGHLIGHT_STYLES[path_prefix]='fg=#8E99B9'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#9BA7C8'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#9BA7C8'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#C7CDDC'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#C7CDDC'
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#C7CDDC'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#8792B0'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#A4AFD0'
ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=#A4AFD0'
ZSH_HIGHLIGHT_STYLES[comment]='fg=#656D82'
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#596074'
