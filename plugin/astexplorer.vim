let s:node_identifier = 0

function! s:BuildTree(node, tree, parent_id, descriptor)
  if type(a:node) == v:t_dict
    if has_key(a:node, 'type') && has_key(a:node, 'loc')
      let current_node_id = s:node_identifier
      if !has_key(a:tree, a:parent_id)
        let a:tree[a:parent_id] = []
      endif
      let node_info = { 'type': a:node.type, 'loc': a:node.loc, 'id': current_node_id, 'descriptor': a:descriptor }
      call add(a:tree[a:parent_id], node_info)
      if has_key(a:node, 'value') && type(a:node.value) != v:t_dict
        let node_info.value = json_encode(a:node.value)
      elseif has_key(a:node, 'operator') && type(a:node.operator) == v:t_string
        let node_info.value = a:node.operator
      endif
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

function! s:BuildOutputList(list, node_id, tree, depth)
  if !has_key(a:tree, a:node_id)
    return
  endif
  for node in a:tree[a:node_id]
    let indent = repeat(' ', a:depth)
    call add(a:list, [indent
          \ . (!empty(node.descriptor) ? node.descriptor . ': ' : '')
          \ . node.type
          \ . (has_key(node.loc, 'identifierName') ? ' - ' . node.loc.identifierName : '')
          \ . (has_key(node, 'value') ? ' - ' . node.value : '')
          \ , node.loc])
    call s:BuildOutputList(a:list, node.id, a:tree, a:depth + 1)
  endfor
endfunction

function! s:AddMatch(match)
  call add(b:ast_explorer_match_list, matchaddpos('AstNode', [a:match]))
endfunction

function! s:AddMatches(locinfo)
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

function! s:GetSourceWindowNumber()
  return win_id2tabwin(b:ast_explorer_source_window)[1]
endfunction

function! s:DeleteMatches()
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

function! s:HighlightNode(locinfo)
  if !exists('b:ast_explorer_previous_cursor_line')
    let b:ast_explorer_previous_cursor_line = 0
  endif
  let current_cursor_line = line('.')
  if current_cursor_line == b:ast_explorer_previous_cursor_line
    return
  endif
  let b:ast_explorer_previous_cursor_line = current_cursor_line
  let window_number = s:GetSourceWindowNumber()
  execute window_number . 'windo call s:DeleteMatches()'
  execute window_number . 'windo call s:AddMatches(a:locinfo)'
  execute printf('%dwindo normal! %dG%d|', window_number, a:locinfo.start.line, a:locinfo.start.column + 1)
  execute window_number . 'wincmd p'
endfunction

function! s:DrawAst(buffer_line_list)
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
  setlocal statusline=ASTExplorer
  setlocal nonumber
  if &colorcolumn
    setlocal colorcolumn=
  endif
  setlocal winfixwidth
endfunction

let s:source_window_to_ast_explorer_mapping = {}

function! s:ASTExplore(filepath, window_id)
  if exists('b:ast_explorer_source_window')
    call remove(s:source_window_to_ast_explorer_mapping, b:ast_explorer_source_window)
    let window_number = s:GetSourceWindowNumber()
    execute window_number . 'windo call s:DeleteMatches()'
    execute window_number . 'wincmd p'
    bdelete
    return
  endif

  if has_key(s:source_window_to_ast_explorer_mapping, a:window_id)
    call s:DeleteMatches()
    let ast_explorer_buffer_id = winbufnr(s:source_window_to_ast_explorer_mapping[a:window_id])
    execute ast_explorer_buffer_id . 'bdelete'
    call remove(s:source_window_to_ast_explorer_mapping, a:window_id)
    return
  endif

  execute 'keepalt 60vsplit ' . a:filepath . '-ast'
  let b:ast_explorer_node_list = []
  let b:ast_explorer_source_window = a:window_id
  let s:source_window_to_ast_explorer_mapping[b:ast_explorer_source_window] = win_getid()

  let ast = system('./node_modules/.bin/parser ' . a:filepath)
  let ast_dict = json_decode(ast)
  let tree = {}
  call s:BuildTree(ast_dict, tree, 'root', '')
  call s:BuildOutputList(b:ast_explorer_node_list, 'root', tree, 0)

  let buffer_line_list = []
  for [buffer_line, locinfo] in b:ast_explorer_node_list
    call add(buffer_line_list, buffer_line)
  endfor
  call s:DrawAst(buffer_line_list)

  augroup ast
    autocmd!
    autocmd CursorMoved <buffer> call s:HighlightNode(b:ast_explorer_node_list[line('.') - 1][1])
  augroup END
endfunction

highlight AstNode guibg=blue ctermbg=blue
command! ASTExplore call s:ASTExplore(expand('%'), win_getid())
