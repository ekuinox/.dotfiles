-- ============================================================
--  WezTerm 設定 (WSL2 専用 / お兄ちゃん用)
--  chezmoi 管理: dot_wezterm.lua -> %USERPROFILE%\.wezterm.lua (Windows のみ)
--  alacritty.toml から移植。変換候補窓がカーソルに追従するのが乗り換え理由。
-- ============================================================

local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

-- ------------------------------------------------------------
--  起動シェル: いつも WSL2 の ubuntu-26.04 に入る
--  (alacritty の program=wsl.exe -d ubuntu-26.04 --cd ~ に相当)
-- ------------------------------------------------------------
config.wsl_domains = {
  {
    name = 'WSL:ubuntu-26.04',
    distribution = 'ubuntu-26.04',
    default_cwd = '~', -- Linux 側のホームから始める
  },
}
config.default_domain = 'WSL:ubuntu-26.04'

-- ------------------------------------------------------------
--  IME: 日本語入力を有効化 (候補窓がカーソル位置に追従する)
-- ------------------------------------------------------------
config.use_ime = true

-- ------------------------------------------------------------
--  ウィンドウまわり
-- ------------------------------------------------------------
config.initial_cols = 120
config.initial_rows = 32
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }
config.window_decorations = 'TITLE | RESIZE' -- alacritty の decorations="Full" 相当
config.window_background_opacity = 1.0
-- タブ/ペインは zellij に任せるので WezTerm のタブバーは消す (alacritty と同じ最小構成)
config.enable_tab_bar = false

-- ------------------------------------------------------------
--  スクロール
-- ------------------------------------------------------------
config.scrollback_lines = 10000

-- ------------------------------------------------------------
--  フォント: UDEV Gothic NF (日本語グリフ内蔵の合成フォント)
-- ------------------------------------------------------------
config.font = wezterm.font('UDEV Gothic NF')
config.font_size = 12.0

-- ------------------------------------------------------------
--  カーソル
-- ------------------------------------------------------------
config.default_cursor_style = 'BlinkingBlock'
config.cursor_blink_rate = 500

-- ============================================================
--  カラーテーマ: Dracula (alacritty の配色をそのまま移植)
-- ============================================================
config.colors = {
  foreground = '#f8f8f2',
  background = '#282a36',

  cursor_bg = '#f8f8f2',
  cursor_fg = '#282a36',
  cursor_border = '#f8f8f2',

  selection_fg = '#f8f8f2',
  selection_bg = '#44475a',

  ansi = {
    '#21222c', -- black
    '#ff5555', -- red
    '#50fa7b', -- green
    '#f1fa8c', -- yellow
    '#bd93f9', -- blue
    '#ff79c6', -- magenta
    '#8be9fd', -- cyan
    '#f8f8f2', -- white
  },
  brights = {
    '#6272a4', -- bright black
    '#ff6e6e', -- bright red
    '#69ff94', -- bright green
    '#ffffa5', -- bright yellow
    '#d6acff', -- bright blue
    '#ff92df', -- bright magenta
    '#a4ffff', -- bright cyan
    '#ffffff', -- bright white
  },
}

-- ============================================================
--  キーバインド (alacritty から移植)
--  ※ タブ/ペインは zellij に任せるので最小限
-- ============================================================
config.keys = {
  -- コピー & ペースト (Ctrl+Shift+C / V)
  { key = 'C', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
  { key = 'V', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },
  -- フォントサイズ変更 (Ctrl + Plus / Minus / 0 でリセット)
  { key = '+', mods = 'CTRL', action = act.IncreaseFontSize },
  { key = '=', mods = 'CTRL', action = act.IncreaseFontSize }, -- Shift 無しの = でも効くように
  { key = '-', mods = 'CTRL', action = act.DecreaseFontSize },
  { key = '0', mods = 'CTRL', action = act.ResetFontSize },
}

return config
