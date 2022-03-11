runtime ftplugin/man.vim

" allow persistent undos
set undodir=~/.config/nvim/undid
set undofile

"turn on search highlighting
set hlsearch

" turn on visual mode character count
set showcmd

"turn on partial search
set incsearch

"turn on case insensitive search
set ignorecase

"turn numbers on
set nu

"turn relative numbers on
set rnu

"split new window to right
set splitright

set nofoldenable


let g:vimwiki_list = [{'path': '~/vimwiki',
                      \ 'syntax': 'markdown', 'ext': '.md'}]

if hostname() == 'abelard.local'
	set nowrap
	let g:vimwiki_list = [{'path': '~/Google Drive/2. - code/212. - vimwiki',
						  \ 'syntax': 'markdown', 'ext': '.md'}]
endif

augroup remember_folds
	autocmd!
	autocmd BufWinLeave * mkview
	autocmd BufWinEnter * silent! loadview
augroup END


" setting leader key
let mapleader = "\<Esc>"


"remaps

" j and k to centre after each move
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

" pairs
inoremap { {}<Left>
inoremap [ []<Left>
inoremap ( ()<Left>
inoremap ' ''<Left>
inoremap " ""<Left>

nnoremap { <C-u>zz
nnoremap } <C-d>zz

" map enter to remove search highlighting
nnoremap <CR> :noh<CR><CR>

nmap <leader>. <Plug>Zoom

nnoremap go g<c-]>
vnoremap go g<c-]>

" leader
" previous / next in buffer
nnoremap <leader>h :bprevious<CR>
nnoremap <leader>t :bnext<CR>
" navigate buffers
nnoremap <leader>' :buffers<CR>:buffer<Space>
" insert single character
nnoremap <leader>, i_<Esc>r
" splits
" horizontal / vertical split
nnoremap <leader>- <C-w>s
nnoremap <leader>s <C-w>v 
" move left / right / down / up through splits
nnoremap <leader>m <C-w>h
nnoremap <leader>w <C-w>l
nnoremap <leader>v <C-w>j
nnoremap <leader>z <C-w>k
" kill split
nnoremap <leader>x <C-w>q
" kill buffer
nnoremap <leader>X :bd<CR>
" open vert split with nerdtree
nnoremap <leader>u :vsp<CR>:Explore<CR>
" open empty file in new buffer
nnoremap <leader>e :enew<CR>

" vimwiki remaps
" toggle todos
nmap <space><space> <Plug>VimwikiToggleListItem
vmap <space><space> <Plug>VimwikiToggleListItem

" clipboard
nnoremap Y "*y

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
Plug 'Mathijs-Bakker/zoom-vim'
Plug 'vimwiki/vimwiki'
Plug 'tpope/vim-surround'
"Plug 'vim-pandoc/vim-pandoc'
"Plug 'vim-pandoc/vim-pandoc-syntax'
"Plug 'godlygeek/tabular'
"Plug 'preservim/vim-markdown'
Plug 'masukomi/vim-markdown-folding'
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

" keep search centred
nnoremap n nzzzv
nnoremap N Nzzzv

autocmd FileType python map <buffer> <leader>r :w<CR>:!clear;python3 %<CR>

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
"


" folding

let g:markdown_folding = 1

let g:vimwiki_global_ext = 0
 
autocmd FileType vimwiki setlocal syntax=markdown

set nocompatible
if has("autocmd")
  filetype plugin indent on
endif
" autocmd FileType vimwiki setlocal foldenable

"let g:vim_markdown_folding_style_pythonic = 1

" autocmd FileType vimwiki setlocal foldenable

" Pandoc 

" let g:vimwiki_global_ext= 0

" function MarkdownLevel()
" 	let h = matchstr(getline(v:lnum), '^#\+')
" 	if empty(h)
" 		return "="     
" 	else       
" 		return ">" . len(h)     
" 	endif 
" endfunction
" au BufEnter *.md setlocal foldexpr=MarkdownLevel()  
" au BufEnter *.md setlocal foldmethod=expr
" 
" 
" https://www.reddit.com/r/vim/comments/lf8mgr/enable_markdown_folding_in_vimwiki/
" 
" 

