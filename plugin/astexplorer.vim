let s:node_identifier = 0

function! s:BuildTree(node, tree, parent_id, descriptor) abort
  if type(a:node) == v:t_dict
    if has_key(a:node, 'type') && type(a:node.type) == v:t_string && has_key(a:node, 'loc')
      let current_node_id = s:node_identifier
      if !has_key(a:tree, a:parent_id)
        let a:tree[a:parent_id] = []
      endif
      let node_info = { 'type': a:node.type, 'loc': a:node.loc, 'id': current_node_id,
            \ 'name': get(a:node, 'name', ''), 'descriptor': a:descriptor, 'extra': {} }
      let insertion_index = 0
      for sibling in a:tree[a:parent_id]
        if sibling.loc.start.line > node_info.loc.start.line ||
              \ sibling.loc.start.line == node_info.loc.start.line &&
              \ sibling.loc.start.column > node_info.loc.start.column
          break
        endif
        let insertion_index += 1
      endfor
      call insert(a:tree[a:parent_id], node_info, insertion_index)
      if has_key(a:node, 'value') && type(a:node.value) != v:t_dict
        let node_info.value = json_encode(a:node.value)
      elseif has_key(a:node, 'operator') && type(a:node.operator) == v:t_string
        let node_info.value = a:node.operator
      endif
      for [key, value] in items(a:node)
        if key !=# 'type' && key !=# 'loc' && key !=# 'value' && key !=# 'operator' && key !=# 'name' &&
              \ (type(value) != v:t_dict || !has_key(value, 'loc')) && type(value) != v:t_list
          let node_info.extra[key] = value
        endif
      endfor
      let s:node_identifier += 1
      for [key, node] in items(a:node)
        call s:BuildTree(node, a:tree, current_node_id, key)
      endfor
    endif
  elseif type(a:node) == v:t_list
    for node in a:node
      call s:BuildTree(node, a:tree, a:parent_id, a:descriptor)
    endfor
  endif
endfunction

function! s:BuildOutputList(list, node_id, tree, depth) abort
  if !has_key(a:tree, a:node_id)
    return
  endif
  for node in a:tree[a:node_id]
    let indent = repeat(' ', a:depth)
    call add(a:list, [indent
          \ . (!empty(node.descriptor) ? node.descriptor . ': ' : '')
          \ . node.type
          \ . (!empty(node.name) ? ' - ' . node.name : '')
          \ . (has_key(node, 'value') ? ' - ' . node.value : '')
          \ , node.loc, json_encode(node.extra)])
    call s:BuildOutputList(a:list, node.id, a:tree, a:depth + 1)
  endfor
endfunction

function! s:AddMatch(match) abort
  call add(b:ast_explorer_match_list, matchaddpos('AstNode', [a:match]))
endfunction

function! s:AddMatches(locinfo) abort
  if !exists('b:ast_explorer_match_list')
    let b:ast_explorer_match_list = []
  endif
  let start = a:locinfo.start
  let end = a:locinfo.end
  if start.line == end.line
    call s:AddMatch([start.line, start.column + 1, end.column - start.column])
    return
  endif
  call s:AddMatch([start.line, start.column + 1, len(getline(start.line)) - start.column])
  for line in range(start.line + 1, end.line - 1)
    call s:AddMatch(line)
  endfor
  call s:AddMatch([end.line, 1, end.column])
endfunction

function! s:DeleteMatches() abort
  if !exists('b:ast_explorer_match_list')
    return
  endif
  for match_id in b:ast_explorer_match_list
    try
      call matchdelete(match_id)
    catch /E803/
      " ignore matches that were already cleared
    endtry
  endfor
  let b:ast_explorer_match_list = []
endfunction

function! s:HighlightNode(locinfo) abort
  if !exists('b:ast_explorer_previous_cursor_line')
    let b:ast_explorer_previous_cursor_line = 0
  endif
  let current_cursor_line = line('.')
  if current_cursor_line == b:ast_explorer_previous_cursor_line
    return
  endif
  let b:ast_explorer_previous_cursor_line = current_cursor_line
  call win_gotoid(b:ast_explorer_source_window)
  call s:DeleteMatches()
  call s:AddMatches(a:locinfo)
  execute printf('normal! %dG%d|', a:locinfo.start.line, a:locinfo.start.column + 1)
  call win_gotoid(t:ast_explorer_window_id)
endfunction

function! s:HighlightNodeForCurrentLine() abort
  call s:HighlightNode(b:ast_explorer_node_list[line('.') - 1][1])
endfunction

function! AstExplorerCurrentParserName() abort
  return b:ast_explorer_current_parser
endfunction

function! s:DrawAst(buffer_line_list) abort
  setlocal modifiable
  setlocal noreadonly
  call setline(1, a:buffer_line_list)
  setlocal nomodifiable
  setlocal readonly
  setlocal nobuflisted
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal cursorline
  setlocal foldmethod=indent
  setlocal shiftwidth=1
  setlocal filetype=ast
  setlocal statusline=ASTExplorer\ [%{AstExplorerCurrentParserName()}]
  setlocal nonumber
  if &colorcolumn
    setlocal colorcolumn=
  endif
  setlocal winfixwidth
  set bufhidden=delete
endfunction

function! s:DeleteMatchesIfAstExplorerGone() abort
  let ast_explorer_window_id = get(t:, 'ast_explorer_window_id')
  if !ast_explorer_window_id ||
        \ getbufvar(winbufnr(ast_explorer_window_id), 'ast_explorer_source_window') != win_getid()
    call s:DeleteMatches()
    augroup ast_source
      autocmd! * <buffer>
    augroup END
  endif
endfunction

function! s:CloseTabIfOnlyContainsExplorer() abort
  if len(gettabinfo(tabpagenr())[0].windows) == 1
    quit
  endif
endfunction

let s:supported_parsers = {
      \   'javascript': {
      \     'default': '@babel/parser',
      \     'executables': {
      \       '@babel/parser': ['node_modules/.bin/parser'],
      \       'babylon': ['node_modules/.bin/babylon'],
      \       'esprima': ['node_modules/.bin/esparse', '--loc'],
      \       'acorn': ['node_modules/.bin/acorn', '--locations'],
      \     }
      \   }
      \ }

function! s:GoToAstExplorerWindow() abort
  let ast_explorer_window_id = get(t:, 'ast_explorer_window_id')
  let ast_explorer_window_number = win_id2win(ast_explorer_window_id)
  if ast_explorer_window_number
    call win_gotoid(ast_explorer_window_id)
  endif
  return ast_explorer_window_number
endfunction

function! s:CloseAstExplorerWindow() abort
  if s:GoToAstExplorerWindow()
    let old_source_window_id = win_id2win(b:ast_explorer_source_window)
    quit
    if old_source_window_id
      execute old_source_window_id . 'windo call s:DeleteMatches()'
    endif
  endif
endfunction

function! s:EchoError(message) abort
  echohl WarningMsg
  echo a:message
  echohl None
endfunction

function! s:OpenAstExplorerWindow(ast, source_window_id, available_parsers, current_parser) abort
  execute 'silent keepalt botright 60vsplit ASTExplorer' . tabpagenr()
  let b:ast_explorer_node_list = []
  let b:ast_explorer_source_window = a:source_window_id
  let b:ast_explorer_available_parsers = a:available_parsers
  let b:ast_explorer_current_parser = a:current_parser
  let t:ast_explorer_window_id = win_getid()

  let tree = {}
  call s:BuildTree(a:ast, tree, 'root', '')
  call s:BuildOutputList(b:ast_explorer_node_list, 'root', tree, 0)

  let buffer_line_list = []
  for [buffer_line; _] in b:ast_explorer_node_list
    call add(buffer_line_list, buffer_line)
  endfor
  call s:DrawAst(buffer_line_list)
  unlet! b:ast_explorer_previous_cursor_line
  call s:HighlightNodeForCurrentLine()

  augroup ast
    autocmd! * <buffer>
    autocmd CursorMoved <buffer> call s:HighlightNodeForCurrentLine()
    autocmd BufEnter <buffer> call s:CloseTabIfOnlyContainsExplorer()
  augroup END
  nnoremap <silent> <buffer> l :echo b:ast_explorer_node_list[line('.') - 1][1]<CR>
  nnoremap <silent> <buffer> i :echo b:ast_explorer_node_list[line('.') - 1][2]<CR>
  nnoremap <silent> <buffer> p :echo b:ast_explorer_available_parsers<CR>
endfunction

function! s:ASTExplore(filepath) abort
  if exists('b:ast_explorer_source_window')
    call s:CloseAstExplorerWindow()
    return
  endif

  let current_source_window_id = win_getid()

  if s:GoToAstExplorerWindow()
    let old_source_window_id = b:ast_explorer_source_window
    call s:CloseAstExplorerWindow()
    if old_source_window_id == current_source_window_id
      return
    else
      call win_gotoid(current_source_window_id)
    endif
  endif

  let filetypes = split(&filetype, '\.')

  let available_parsers = {}
  let supported_parsers_for_filetypes = []
  let default_parsers_for_filetypes = []
  for filetype in filetypes
    let filetype_parsers = get(s:supported_parsers, filetype, {})
    if !empty(filetype_parsers)
      call add(default_parsers_for_filetypes, filetype_parsers.default)
      for [parser_name, executable] in items(filetype_parsers.executables)
        call add(supported_parsers_for_filetypes, parser_name)
        let [parser_executable; flags] = executable
        let executable_file = findfile(parser_executable, ';')
        if executable(executable_file)
          let available_parsers[parser_name] = fnamemodify(executable_file, ':p') . ' ' . join(flags)
        endif
      endfor
    endif
  endfor

  if empty(supported_parsers_for_filetypes)
    call s:EchoError('No supported parsers for filetype "' . &filetype . '"')
    return
  endif

  if empty(available_parsers)
    call s:EchoError('No supported parsers found for filetype "' . &filetype . '". '
          \ . 'Install one of [' . join(supported_parsers_for_filetypes, ', ') . '].')
    return
  endif

  let current_parser = ''
  for default_parser in default_parsers_for_filetypes
    if has_key(available_parsers, default_parser)
      let current_parser = default_parser
    endif
  endfor
  if empty(current_parser)
    let current_parser = keys(available_parsers)[0]
  endif

  augroup ast_source
    autocmd! * <buffer>
    autocmd BufEnter <buffer> call s:DeleteMatchesIfAstExplorerGone()
  augroup END

  let ast_json = system(available_parsers[current_parser] . ' ' . a:filepath)
  let ast_dict = json_decode(ast_json)

  call s:OpenAstExplorerWindow(ast_dict, current_source_window_id, available_parsers, current_parser)
endfunction

function! s:ASTJumpToNode() abort
  if exists('b:ast_explorer_source_window')
    return
  endif
  let window_id = win_getid()
  let cursor_line = line('.')
  let cursor_column = col('.') - 1
  if !win_id2win(get(t:, 'ast_explorer_window_id'))
    ASTExplore
  endif
  call win_gotoid(get(t:, 'ast_explorer_window_id'))
  let buffer_line = 1
  let jump_node_buffer_line = 1
  for [_, locinfo; _] in b:ast_explorer_node_list
    if locinfo.start.line > cursor_line
      break
    endif
    let start = locinfo.start
    let end = locinfo.end
    if start.line == cursor_line && cursor_column >= start.column &&
          \ (cursor_line < end.line || cursor_line == end.line && cursor_column < end.column) ||
          \ start.line < cursor_line && cursor_line < end.line ||
          \ end.line == cursor_line && cursor_column < end.column &&
          \ (cursor_line > start.line || cursor_line == start.line && cursor_column >= start.column)
      let jump_node_buffer_line = buffer_line
    endif
    let buffer_line += 1
  endfor
  execute 'normal! zR' . jump_node_buffer_line . 'Gzz'
endfunction

highlight AstNode guibg=blue ctermbg=blue

command! ASTExplore call s:ASTExplore(expand('%'))
command! ASTViewNode call s:ASTJumpToNode()
