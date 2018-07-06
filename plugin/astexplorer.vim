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
    let indent = ''
    for _ in range(0, a:depth - 1)
      let indent = indent . ' '
    endfor
    call add(a:list, [indent
          \ . (node.descriptor != '' ? node.descriptor . ': ' : '')
          \ . node.type
          \ . (has_key(node.loc, 'identifierName') ? ' - ' . node.loc.identifierName : '')
          \ . (has_key(node, 'value') ? ' - ' . node.value : '')
          \ , node.loc])
    call s:BuildOutputList(a:list, node.id, a:tree, a:depth + 1)
  endfor
endfunction

let s:match_list = []

function! s:AddMatches(locinfo)
  if a:locinfo.start.line == a:locinfo.end.line
    call add(s:match_list, matchaddpos('AstNode', [[a:locinfo.start.line, a:locinfo.start.column + 1, a:locinfo.end.column - a:locinfo.start.column]]))
    return
  endif
  call add(s:match_list, matchaddpos('AstNode', [[a:locinfo.start.line, a:locinfo.start.column + 1, max([1, len(getline(a:locinfo.start.line)) - a:locinfo.start.column])]]))
  for line in range(a:locinfo.start.line + 1, a:locinfo.end.line - 1)
    call add(s:match_list, matchaddpos('AstNode', [line]))
  endfor
  call add(s:match_list, matchaddpos('AstNode', [[a:locinfo.end.line, 1, a:locinfo.end.column]]))
endfunction

function! s:SelectNode(locinfo, window_id)
  let window_number = win_id2tabwin(a:window_id)[1]
  for match_id in s:match_list
    try
      execute window_number . 'windo call matchdelete(' . match_id . ')'
    catch /E803/
      " ignore matches that were already cleared
    endtry
  endfor
  let s:match_list = []
  execute window_number . 'windo call s:AddMatches(a:locinfo)'
  execute window_number . 'windo normal ' . a:locinfo.start.line . 'G' . (a:locinfo.start.column + 1) . '|'
  execute window_number . 'wincmd p'
endfunction

let s:last_line = 0

function! s:SelectNodeIfLineChanged(locinfo, source_window)
  if line('.') != s:last_line
    let s:last_line = line('.')
    call s:SelectNode(a:locinfo, a:source_window)
  endif
endfunction

function! s:ASTExplore(filepath, window_id)
  let ast = system('./node_modules/.bin/parser ' . a:filepath)
  execute 'vsplit ' . a:filepath . '-ast'
  let ast_dict = json_decode(ast)
  let tree = {}
  call s:BuildTree(ast_dict, tree, 'root', '')
  let b:list = []
  call s:BuildOutputList(b:list, 'root', tree, 0)
  setlocal modifiable
  setlocal noreadonly
  " call setline(1, split(ast, "\n"))
  let output_list = []
  let b:source_window = a:window_id
  for [output, locinfo] in b:list
    call add(output_list, output)
  endfor
  call setline(1, output_list)
  nnoremap <silent> <buffer> <Enter> :call <SID>SelectNode(b:list[line('.') - 1][1], b:source_window)<CR>
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
  augroup ast
    autocmd!
    autocmd CursorMoved <buffer> call s:SelectNodeIfLineChanged(b:list[line('.') - 1][1], b:source_window)
  augroup END
endfunction

highlight AstNode guibg=blue ctermbg=blue
command! ASTExplore call s:ASTExplore(expand('%'), win_getid())
