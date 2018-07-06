let s:node_identifier = 0

function! s:BuildOutputAst(node, node_map, parent_id, descriptor)
  if type(a:node) == v:t_dict
    if has_key(a:node, 'type') && has_key(a:node, 'loc')
      let current_node_id = s:node_identifier
      if !has_key(a:node_map, a:parent_id)
        let a:node_map[a:parent_id] = []
      endif
      let node_info = { 'type': a:node.type, 'loc': a:node.loc, 'id': current_node_id, 'descriptor': a:descriptor }
      call add(a:node_map[a:parent_id], node_info)
      if has_key(a:node, 'value') && type(a:node.value) != v:t_dict
        let node_info.value = json_encode(a:node.value)
      elseif has_key(a:node, 'operator') && type(a:node.operator) == v:t_string
        let node_info.value = a:node.operator
      endif
      let s:node_identifier += 1
      for [key, node] in items(a:node)
        call s:BuildOutputAst(node, a:node_map, current_node_id, key)
      endfor
    endif
  elseif type(a:node) == v:t_list
    for node in a:node
      call s:BuildOutputAst(node, a:node_map, a:parent_id, a:descriptor)
    endfor
  endif
endfunction

function! s:BuildOutputList(list, map_id, node_map, depth)
  if !has_key(a:node_map, a:map_id)
    return
  endif
  for node in a:node_map[a:map_id]
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
    call s:BuildOutputList(a:list, node.id, a:node_map, a:depth + 1)
  endfor
endfunction

function! s:SelectNode(locinfo, window_id)
  let window_number = win_id2tabwin(a:window_id)[1]
  execute window_number . 'windo normal ' . a:locinfo.start.line . 'G'
        \ . (a:locinfo.start.column + 1) . '|v' . a:locinfo.end.line . 'G' . a:locinfo.end.column . '|'
endfunction

function! s:ASTExplore(filepath, window_id)
  let ast = system('./node_modules/.bin/parser ' . a:filepath)
  execute 'vsplit ' . a:filepath . '-ast'
  let ast_dict = json_decode(ast)
  let node_map = {}
  call s:BuildOutputAst(ast_dict, node_map, 'root', '')
  let b:list = []
  call s:BuildOutputList(b:list, 'root', node_map, 0)
  setlocal modifiable
  setlocal noreadonly
  " call setline(1, split(ast, "\n"))
  let output_list = []
  let b:source_window = a:window_id
  for [output, locinfo] in b:list
    call add(output_list, output)
  endfor
  call setline(1, output_list)
  nnoremap <buffer> <Enter> :call <SID>SelectNode(b:list[line('.') - 1][1], b:source_window)<CR>
  setlocal nomodifiable
  setlocal readonly
  setlocal nobuflisted
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal cursorline
endfunction

command! ASTExplore call s:ASTExplore(expand('%'), win_getid())
