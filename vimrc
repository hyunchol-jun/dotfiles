set nocompatible

" Turn on 'detection', 'plugin', 'indent' at once
filetype plugin indent on

" Indent javascript, css inside html tags properly
let g:html_indent_script1 = "inc"
let g:html_indent_style1 = "inc"

set nu	    " Enable line numbers
set relativenumber
syntax on	" Enable syntax highlighting
set showmatch " show matching braces when text indicator is over them

colorscheme iceberg
set background=dark

" highlight current line, but only in active window
augroup CursorLineOnlyInActiveWindow
    autocmd!
    autocmd VimEnter,WinEnter,BufWinEnter * setlocal cursorline
    autocmd WinLeave * setlocal nocursorline
augroup END

" The backspace key has slightly unintuitive behavior by default. For example,
" by default, you can't backspace before the insertion point set with 'i'.
" This configuration makes backspace behave more reasonably, in that you can
" backspace over anything.
set backspace=indent,eol,start

" By default, Vim doesn't let you hide a buffer (i.e. have a buffer that isn't
" shown in any window) that has unsaved changes. This is to prevent you from "
" forgetting about unsaved changes and then quitting e.g. via `:qa!`. We find
" hidden buffers helpful enough to disable this protection. See `:help hidden`
" for more information on this.
set hidden

set colorcolumn=80

" This setting makes search case-insensitive when all characters in the string
" being searched are lowercase. However, the search becomes case-sensitive if
" it contains any capital letters. This makes searching more convenient.
set ignorecase
set smartcase

" Always show the status line at the bottom, even if you only have one window
" open
set laststatus=2

" Show the filename in the window titlebar
set title

" Use 4 spaces instead of tabs during formatting
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4

" tab completion for files/bufferss
set wildmode=longest,list
set wildmenu

" Enable searching as you type, rather than waiting till you press enter.
set incsearch
set hlsearch	" Enable highlight search

set scrolloff=5 " show lines above and below cursor (when possible)

" Unbind some useless/annoying default key bindings.
nmap Q <Nop> " 'Q' in normal mode enters Ex mode. You almost never want this.

" Disable audible bell because it's annoying.
set noerrorbells visualbell t_vb=

set termwinsize=12x0    " Set terminal size
set mouse+=a             " Enable mouse drag on window splits

" open new split panes to right and bottom, which feels more natural
set splitbelow
set splitright

" Show “invisible” characters
set lcs=tab:▸\ ,trail:·,eol:¬,nbsp:_
set list

" Don't reset cursor to start of line when moving around.
set nostartofline

" Show the cursor position
set ruler

" quicker window movement
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-h> <C-w>h
nnoremap <C-l> <C-w>l

" shortcut for emptying search result to make highlights disappear
nnoremap \\ :let @/=""<CR>

" shortcut for jumping to the next error in ale
nmap <silent> <C-e> <Plug>(ale_next_wrap)

" disable linting when opening, enable when saving
" let g:ale_lint_on_enter = 0
" let g:ale_lint_on_save = 1

" change the symbols for error, warning
let g:ale_sign_error = '●'
let g:ale_sign_warning = '.'

let g:ale_linters = {
\    'cpp': ['cc'],
\    'python': ['flake8'],
\}

" Only run linters named in ale_linters settings.
let g:ale_linters_explicit = 1

let g:ale_fixers = {
\    '*': ['remove_trailing_lines', 'trim_whitespace'],
\    'python': ['black', 'isort'],
\}

let g:ale_fix_on_save = 1

let g:ale_completion_enabled = 1
set omnifunc=ale#completion#OmniFunc

let g:AutoPairsShortcutToggle = '<C-P>'

let NERDTreeShowBookmarks = 1   " Show the bookmarks table
let NERDTreeShowHidden = 1      " Show hidden files
let NERDTreeShowLineNumbers = 0 " Hide line numbers
let NERDTreeMinimalMenu = 1     " Use the minimal menu (m)
let NERDTreeWinPos = 'left'     " Panel opens on the left side
let NERDTreeWinSize = 31        " Set panel width to 31 columns

" open/close NERDTree(\f)
nnoremap <Leader>f :NERDTreeToggle<CR>

" close when opening file
let NERDTreeQuitOnOpen = 1

" Close the tab if NERDTree is the only window remaining in it.
autocmd BufEnter * if winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif

" open NERDTree when starting vim with no arguments
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 0 && !exists("s:std_in") | NERDTree | endif

" auto delete buffer when deleting with nerdTree
let NERDTreeAutoDeleteBuffer = 1

" make it prettier
let NERDTreeMinimalUI = 1
let NERDTreeDirArrows = 2
