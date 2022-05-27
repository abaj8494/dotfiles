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

"set nofoldenable

" vimwiki lets
"let g:vimwiki_list = [{'path': '~/vimwiki',
"                      \ 'syntax': 'markdown', 'ext': '.md'}]

" diary lets
let g:calendar_monday = 1
let g:calendar_weeknm = 2 

" if hostname() == 'abelard.local'
" endif
let g:vimwiki_list = [{'path': '$HOME/Google Drive/2. - code/212. - vimwiki/212.00 - cs',
					  \ 'syntax': 'markdown', 'ext': '.md'},
					  \ {'path': '$HOME/Google Drive/2. - code/212. - vimwiki/212.01 - pkm',
					  \ 'syntax': 'markdown', 'ext': '.md'}]


""augroup remember_folds
"	autocmd!
"	autocmd BufWinLeave * mkview
"	autocmd BufWinEnter * silent! loadview
"augroup END


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


" pairs
inoremap { {}<Left>
inoremap [ []<Left>
inoremap ( ()<Left>
inoremap ' ''<Left>
inoremap " ""<Left>
inoremap $ $$<Left>

nnoremap { <C-u>zz
nnoremap } <C-d>zz

" map enter to remove search highlighting
nnoremap <CR> :noh<CR><CR>

nmap <leader>. <Plug>Zoom

" opens tag under cursor
nnoremap go g<c-]>
vnoremap go g<c-]>

" remaps backspace to file explorer in normal mode
nnoremap <backspace> :E<CR>


" leader
" previous / next in buffer
nnoremap <leader>h :bprevious<CR>
nnoremap <leader>t :bnext<CR>
" navigate buffers
nnoremap <leader>' :buffers<CR>:buffer<Space>
" insert single character
nnoremap <leader>, a_<Esc>r
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
" open config
nnoremap <leader>r :RC<CR>

" vimwiki remaps
" toggle todos
nmap <space><space> <Plug>VimwikiToggleListItem
vmap <space><space> <Plug>VimwikiToggleListItem
" open vimwiki
nmap <space>v <Plug>VimwikiIndex
vmap <space>v <Plug>VimwikiIndex
" diary
" open vimdiary
nmap <space>V <Plug>VimwikiDiaryIndex
vmap <space>V <Plug>VimwikiDiaryIndex
" create today entry
nmap <space>w <Plug>VimwikiMakeDiaryNote
vmap <space>w <Plug>VimwikiMakeDiaryNote
" create yesterday entry
nmap <space>m <Plug>VimwikiMakeYesterdayDiaryNote
vmap <space>m <Plug>VimwikiMakeYesterdayDiaryNote
" create tomorrow entry
nmap <space>z <Plug>VimwikiMakeTomorrowDiaryNote
vmap <space>z <Plug>VimwikiMakeTomorrowDiaryNote
" remap diary next / previous day
nmap <space>t <Plug>VimwikiDiaryNextDay
vmap <space>t <Plug>VimwikiDiaryNextDay
nmap <space>h <Plug>VimwikiDiaryPrevDay
vmap <space>h <Plug>VimwikiDiaryPrevDay
" diary calendar
nmap <space>c :CalendarVR<CR>
vmap <space>c :CalendarVR<CR>

nmap <space>g <Plug>VimwikiDiaryGenerateLinks
vmap <space>g :<Plug>VimwikiDiaryGenerateLinks


" clipboard
nnoremap Y "*y

nnoremap <space>o o<Esc>
nnoremap <space>O O<Esc>


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
Plug 'lervag/vimtex'
"Plug 'xuhdev/vim-latex-live-preview', { 'for': 'tex' }
"Plug 'vim-pandoc/vim-pandoc'
"Plug 'vim-pandoc/vim-pandoc-syntax'
"Plug 'godlygeek/tabular'
"Plug 'preservim/vim-markdown'
Plug 'masukomi/vim-markdown-folding'
Plug 'dhruvasagar/vim-table-mode'
Plug 'mattn/calendar-vim'
Plug 'https://github.com/wgurecky/vimSum.git', { 'do' : ':UpdateRemotePlugins' }
Plug 'preservim/nerdtree'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'renerocksai/telekasten.nvim'
Plug 'michal-h21/vim-zettel'
call plug#end()


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

let g:vimwiki_global_ext = 0

let g:vimwiki_folding = 'custom'
augroup folds
	autocmd FileType vimwiki set foldexpr=MarkdownFold()
	autocmd FileType vimwiki set foldmethod=expr
	autocmd FileType vimwiki set syntax=markdown
	autocmd FileType vimwiki set nofoldenable
augroup END


" commands
command RC e $MYVIMRC

" vimwiki autogroup
"augroup vimwiki
"	autocmd!
"augroup end
"autocmd BufRead * if expand('%') =~ "index" | set syntax=vimwiki | endif

autocmd BufEnter diary.md VimwikiDiaryGenerateLinks
autocmd BufEnter index.md set syntax=vimwiki

let g:vimtex_view_general_viewer = 'zathura'


" nerdtree stuff in flux

autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif

let NERDTreeMinimalUI=1

map <space>e :NERDTreeToggle<CR>

" telescope in flux
map <C-u> :Telescope live_grep<CR>

" quick fix list navigation
nnoremap <leader>g :cprev<CR>
nnoremap <leader>c :cnext<CR>
nnoremap <space>q :cexpr []<cr> 

function! GetBufferList()
  redir =>buflist
  silent! ls!
  redir END
  return buflist
endfunction

function! ToggleList(bufname, pfx)
  let buflist = GetBufferList()
  for bufnum in map(filter(split(buflist, '\n'), 'v:val =~ "'.a:bufname.'"'), 'str2nr(matchstr(v:val, "\\d\\+"))')
    if bufwinnr(bufnum) != -1
      exec(a:pfx.'close')
      return
    endif
  endfor
  if a:pfx == 'l' && len(getloclist(0)) == 0
      echohl ErrorMsg
      echo "Location List is Empty."
      return
  endif
  let winnr = winnr()
  exec(a:pfx.'open')
  if winnr() != winnr
    wincmd p
  endif
endfunction

nmap <silent> <leader>l :call ToggleList("Location List", 'l')<CR>
nmap <silent> <leader>q :call ToggleList("Quickfix List", 'c')<CR>


" placing after table-mode plugin is loaded
nnoremap <space>[ [\|
nnoremap <space>] ]\|
nnoremap <space>{ {\|
nnoremap <space>} }\|



" telekasten
lua << END
local home = vim.fn.expand("~/Google Drive/2. - code/212. - vimwiki/212.01 - pkm")
-- NOTE for Windows users:
-- - don't use Windows
-- - try WSL2 on Windows and pretend you're on Linux
-- - if you **must** use Windows, use "/Users/myname/zettelkasten" instead of "~/zettelkasten"
-- - NEVER use "C:\Users\myname" style paths
-- - Using `vim.fn.expand("~/zettelkasten")` should work now but mileage will vary with anything outside of finding and opening files
require('telekasten').setup({
    home         = home,

    -- if true, telekasten will be enabled when opening a note within the configured home
    take_over_my_home = true,

    -- auto-set telekasten filetype: if false, the telekasten filetype will not be used
    --                               and thus the telekasten syntax will not be loaded either
    auto_set_filetype = true,

    -- dir names for special notes (absolute path or subdir name)
    dailies      = home .. '/' .. 'daily',
    weeklies     = home .. '/' .. 'weekly',
    templates    = home .. '/' .. 'templates',

    -- image (sub)dir for pasting
    -- dir name (absolute path or subdir name)
    -- or nil if pasted images shouldn't go into a special subdir
    image_subdir = "img",

    -- markdown file extension
    extension    = ".md",

    -- prefix file with uuid
    prefix_title_by_uuid = false,
    -- file uuid type ("rand" or input for os.date()")
    uuid_type = "%Y%m%d%H%M",
    -- UUID separator
    uuid_sep = "-",

    -- following a link to a non-existing note will create it
    follow_creates_nonexisting = true,
    dailies_create_nonexisting = true,
    weeklies_create_nonexisting = true,

    -- skip telescope prompt for goto_today and goto_thisweek
    journal_auto_open = false,

    -- template for new notes (new_note, follow_link)
    -- set to `nil` or do not specify if you do not want a template
    template_new_note = home .. '/' .. 'templates/new_note.md',

    -- template for newly created daily notes (goto_today)
    -- set to `nil` or do not specify if you do not want a template
    template_new_daily = home .. '/' .. 'templates/daily.md',

    -- template for newly created weekly notes (goto_thisweek)
    -- set to `nil` or do not specify if you do not want a template
    template_new_weekly= home .. '/' .. 'templates/weekly.md',

    -- image link style
    -- wiki:     ![[image name]]
    -- markdown: ![](image_subdir/xxxxx.png)
    image_link_style = "markdown",

    -- default sort option: 'filename', 'modified'
    sort = "filename",

    -- integrate with calendar-vim
    plug_into_calendar = true,
    calendar_opts = {
        -- calendar week display mode: 1 .. 'WK01', 2 .. 'WK 1', 3 .. 'KW01', 4 .. 'KW 1', 5 .. '1'
        weeknm = 4,
        -- use monday as first day of week: 1 .. true, 0 .. false
        calendar_monday = 1,
        -- calendar mark: where to put mark for marked days: 'left', 'right', 'left-fit'
        calendar_mark = 'left-fit',
    },

    -- telescope actions behavior
    close_after_yanking = false,
    insert_after_inserting = true,

    -- tag notation: '#tag', ':tag:', 'yaml-bare'
    tag_notation = "#tag",

    -- command palette theme: dropdown (window) or ivy (bottom panel)
    command_palette_theme = "dropdown",

    -- tag list theme:
    -- get_cursor: small tag list at cursor; ivy and dropdown like above
    show_tags_theme = "ivy",

    -- when linking to a note in subdir/, create a [[subdir/title]] link
    -- instead of a [[title only]] link
    subdirs_in_links = true,

    -- template_handling
    -- What to do when creating a new note via `new_note()` or `follow_link()`
    -- to a non-existing note
    -- - prefer_new_note: use `new_note` template
    -- - smart: if day or week is detected in title, use daily / weekly templates (default)
    -- - always_ask: always ask before creating a note
    template_handling = "smart",

    -- path handling:
    --   this applies to:
    --     - new_note()
    --     - new_templated_note()
    --     - follow_link() to non-existing note
    --
    --   it does NOT apply to:
    --     - goto_today()
    --     - goto_thisweek()
    --
    --   Valid options:
    --     - smart: put daily-looking notes in daily, weekly-looking ones in weekly,
    --              all other ones in home, except for notes/with/subdirs/in/title.
    --              (default)
    --
    --     - prefer_home: put all notes in home except for goto_today(), goto_thisweek()
    --                    except for notes with subdirs/in/title.
    --
    --     - same_as_current: put all new notes in the dir of the current note if
    --                        present or else in home
    --                        except for notes/with/subdirs/in/title.
    new_note_location = "smart",

    -- should all links be updated when a file is renamed
    rename_update_links = true,
})
END


" vim-zettel
let g:zettel_fzf_command = "rg --column --line-number --ignore-case --no-heading --color=always"

let g:zettel_options = [{}, {"front_matter" : [["tags", ""], ["type","note"]], "template" :  "~/mytemplate.tpl"}]



" telescope remaps

nnoremap <Leader>fw :lua require'telescope.builtin'.grep_string(require('telescope.themes').get_dropdown({}))<CR>

nnoremap <Leader>ff :lua require'telescope.builtin'.find_files(require('telescope.themes').get_dropdown({}))<CR>

nnoremap <Leader>fg :lua require'telescope.builtin'.live_grep(require('telescope.themes').get_dropdown({}))<CR>

nnoremap <Leader>fb :lua require'telescope.builtin'.buffers(require('telescope.themes').get_dropdown({}))<CR>

nnoremap <leader>zf :lua require('telekasten').find_notes()<CR>
nnoremap <leader>zd :lua require('telekasten').find_daily_notes()<CR>
nnoremap <leader>zb :lua require('telekasten').show_backlinks()<CR>
nnoremap <leader>zg :lua require('telekasten').search_notes()<CR>
nnoremap <leader>zz :lua require('telekasten').follow_link()<CR>
nnoremap <leader>zn :lua require('telekasten').new_note()<CR>

" on hesitation, bring up the panel
nnoremap <leader>Z :lua require('telekasten').panel()<CR>

