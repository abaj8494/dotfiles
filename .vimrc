"turn numbers on
set nu

"turn relative numbers on
set rnu

" setting leader key
let mapleader = " "


"remaps

" centre remaps
nnoremap j jzz
nnoremap k kzz
nnoremap n nzzzv
nnoremap N Nzzzv
nnoremap <CR> <CR>zz
inoremap <CR> <C-\><C-O><C-E><CR>
inoremap <BS> <BS><C-O>zz
inoremap <right> <right><C-O>zz
inoremap <left> <left><C-O>zz
inoremap <up> <up><C-O>zz
inoremap <down> <down><C-O>zz

"letter t to l
nnoremap t l
vnoremap t l

" tab and shift tab
vnoremap <Tab> >gv
vnoremap <S-Tab> <gv
nnoremap <S-Tab> <<
inoremap <S-Tab> <C-d>

" fzf
nnoremap <C-u> :Files<Cr>

" bracket & quote pairs
inoremap { {}<Left>
inoremap [ []<Left>
inoremap ( ()<Left>
inoremap ' ''<Left>
inoremap " ""<Left>

" leader
nnoremap <leader>c :bprevious<CR>
nnoremap <leader>r :bnext<CR> 
nnoremap <leader><leader> :buffers<CR>:buffer<Space>

" clipboard
nnoremap Y "*y
nnoremap P "*p

" /remaps

"forbid mouse from selecting numbers
se mouse+=a

"fixing indentation
set shiftwidth=4
set tabstop=4
set softtabstop=0

" getting rid of 'save buffer to exit'
set hidden


"this method works on both my cse ssh and personal iterm
let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=1\x7\<Esc>\\"
let &t_SR = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=2\x7\<Esc>\\"
let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=0\x7\<Esc>\\"
"this is however marginally slower. to fix this we have
set ttimeout
set ttimeoutlen=1
set ttyfast


"allow arrow keys to move across lines
set whichwrap+=<,>,h,l,[,]

"plug install (the manager)
let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif


call plug#begin('~/.vim/plugged')
" notic how I call the plug betwixt the call begin & end
" tokyonight theme
Plug 'ghifarit53/tokyonight-vim'
" fuzzy finder fzf
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
call plug#end()
"set termguicolors

let g:tokyonight_style = 'night' " available: night, storm
let g:tokyonight_enable_italic = 1
colorscheme tokyonight

"set gvim font size
set guifont=Menlo-Regular:h16

"getting extra text targets
Plug 'wellle/targets.vim'

" ruler at column 80
set colorcolumn=80


" moving text (primeagen)
" vnoremap J :m '>+1<CR>gv=gv
" vnoremap K :m '<-2<CR>gv=gv
" inoremap <C-j> :m .+1<CR>==
" inoremap <C-k> :m .-2<CR>==
" nnoremap <leader>j :m .+1<CR>==
" nnoremap <leader>k :m .-2<CR>==

" telescope plugin -> this only works on neovim!!
" Plug 'nvim-lua/plenary.nvim'
" Plug 'nvim-telescope/telescope.nvim'

