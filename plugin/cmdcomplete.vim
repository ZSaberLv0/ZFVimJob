
function! ZFJobCmdComplete(ArgLead, CmdLine, CursorPos)
    let ret = ZFJobCmdComplete_env(a:ArgLead, a:CmdLine, a:CursorPos)
    if !empty(ret)
        return ret
    endif

    let paramIndex = ZFJobCmdComplete_paramIndex(a:ArgLead, a:CmdLine, a:CursorPos)
    if paramIndex == 0
        if get(g:, 'ZFJobCmdComplete_completeVimCmd', 0)
            let ret = ZFJobCmdComplete_vimcmd(a:ArgLead, a:CmdLine, a:CursorPos)
        else
            let ret = ZFJobCmdComplete_shellcmd(a:ArgLead, a:CmdLine, a:CursorPos)
        endif
        if empty(ret)
            let ret = ZFJobCmdComplete_file(a:ArgLead, a:CmdLine, a:CursorPos)
        endif
        return ret
    endif
    return ZFJobCmdComplete_file(a:ArgLead, a:CmdLine, a:CursorPos)
endfunction

" ============================================================
function! ZFJobCmdComplete_paramIndex(ArgLead, CmdLine, CursorPos)
    let AL = s:fixArgLead(a:ArgLead)
    let paramList = s:cmdSplit(a:CmdLine)
    " (`|` is cursor pos)
    " offset==0 && empty(AL.ArgLead) : 1 - 0
    "     ls |
    " offset==0 && !empty(AL.ArgLead) : 2 - 0 - 1
    "     ls abc|
    " offset==1 && empty(AL.ArgLead) : 2 - 1
    "     ZFAsyncRun ls |
    " offset==1 && !empty(AL.ArgLead) : 3 - 1 - 1
    "     ZFAsyncRun ls abc|
    let offset = 0
    if get(g:, 'ZFJobCmdComplete_excludeFirstCmd', 1)
        if len(paramList) >= 1 && exists(':' . paramList[0])
            let offset = 1
        endif
    endif
    if empty(AL.ArgLead)
        return len(paramList) - offset
    else
        return len(paramList) - offset - 1
    endif
endfunction
function! ZFJobCmdComplete_filter(list, prefix)
    let i = len(a:list) - 1
    while i >= 0
        if match(tolower(a:list[i]), tolower(a:prefix)) != 0
            call remove(a:list, i)
        endif
        let i -= 1
    endwhile
endfunction

" ============================================================
function! ZFJobCmdComplete_env(ArgLead, CmdLine, CursorPos)
    " (?<!\\)\$[a-zA-Z0-9_]*$
    let pos = match(a:ArgLead, '\%(\\\)\@<!\$[a-zA-Z0-9_]*$')
    if pos < 0
        return []
    endif
    let pos += 1

    if exists('*getcompletion') && !get(g:, 'ZFJobCmdComplete_preferBuiltin', 0)
        let m = {}
        for item in getcompletion('', 'environment')
            " [:\\\(\[\{].*
            let m[substitute(item, '[:\\([{].*', '', 'g')] = 1
        endfor
        let ret = keys(m)
    else
        let cmd = 'export'
        if has('win32') || has('win64')
            if has('unix') && executable('sh')
                let cmd = 'sh -c export'
            else
                let cmd = 'set'
            endif
        endif
        let lines = split(system(cmd), "\n")
        let ret = []
        for line in lines
            " ^(export )?[a-zA-Z0-9_]+=
            if match(line, '^\(export \)\=[a-zA-Z0-9_]\+=') >= 0
                " ^(export )?([a-zA-Z0-9_]+)=.*$
                call add(ret, substitute(line, '^\(export \)\=\([a-zA-Z0-9_]\+\)=.*$', '\2', ''))
            endif
        endfor
    endif

    if pos < len(a:ArgLead)
        call ZFJobCmdComplete_filter(ret, strpart(a:ArgLead, pos))
    endif
    let prefix = strpart(a:ArgLead, 0, pos)
    let i = len(ret) - 1
    while i >= 0
        let ret[i] = prefix . ret[i]
        let i -= 1
    endwhile
    return ret
endfunction

function! ZFJobCmdComplete_shellcmd(ArgLead, CmdLine, CursorPos)
    let AL = s:fixArgLead(a:ArgLead)
    if exists('*getcompletion') && !get(g:, 'ZFJobCmdComplete_preferBuiltin', 0)
        return s:restoreArgLead(s:fixPath(getcompletion(AL.ArgLead, 'shellcmd')), AL)
    endif
    if match(AL.ArgLead, '[/\\]') >= 0
        return s:restoreArgLead(s:fixPath(split(glob(AL.ArgLead . '*', 1), "\n")), AL)
    endif

    let map = {}
    if (has('win32') || has('win64')) && !has('unix')
        let pathList = split($PATH, ';')
    else
        let pathList = split($PATH, ':')
    endif
    for path in pathList
        let pattern = substitute(path, '\\', '/', 'g') . '/' . AL.ArgLead . '*'
        let files = split(glob(pattern, 1), "\n")
        for file in files
            if !isdirectory(file)
                let map[fnamemodify(file, ':t')] = 1
            endif
        endfor
    endfor
    return keys(map)
endfunction

function! ZFJobCmdComplete_vimcmd(ArgLead, CmdLine, CursorPos)
    let AL = s:fixArgLead(a:ArgLead)
    if exists('*getcompletion') && !get(g:, 'ZFJobCmdComplete_preferBuiltin', 0)
        return s:restoreArgLead(s:fixPath(getcompletion(AL.ArgLead, 'command')), AL)
    endif
    return []
endfunction

function! ZFJobCmdComplete_file(ArgLead, CmdLine, CursorPos)
    let AL = s:fixArgLead(a:ArgLead)
    if exists('*getcompletion') && !get(g:, 'ZFJobCmdComplete_preferBuiltin', 0)
        return s:restoreArgLead(s:fixPath(getcompletion(AL.ArgLead, 'file')), AL)
    else
        return s:restoreArgLead(s:fixPath(split(glob(AL.ArgLead . '*', 1), "\n")), AL)
    endif
endfunction

function! s:cmdSplit(cmd)
    let ret = []
    for item in split(substitute(a:cmd, '\\ ', '_ZF_SPACE_ZF_', 'g'), ' ')
        call add(ret, substitute(item, '_ZF_SPACE_ZF_', '\\ ', 'g'))
    endfor
    return ret
endfunction

function! s:fixPath(list)
    let ret = []
    for item in a:list
        let t = substitute(item, '\\', '/', 'g')
        " ([^\/])\/+$
        let t = substitute(t, '\([^\/]\)\/\+$', '\1', '')
        if isdirectory(CygpathFix_absPath(t))
            let t .= '/'
        endif
        let t = substitute(t, ' ', '\\ ', 'g')
        call add(ret, t)
    endfor
    return ret
endfunction

" 'ls' => '' and 'ls'
" 'ls ' => 'ls ' and ''
" 'ls abc' => 'ls ' and 'abc'
" 'ls c:' => 'ls ' and 'c:/'
"
" return: {
"   'prefix' : '',
"   'ArgLead' : '',
" }
function! s:fixArgLead(ArgLead)
    let tmp = s:cmdSplit(a:ArgLead)
    if empty(tmp)
        return {
                    \   'prefix' : '',
                    \   'ArgLead' : '',
                    \ }
    endif
    if a:ArgLead[len(a:ArgLead) - 1] == ' '
        return {
                    \   'prefix' : join(tmp, ' ') . ' ',
                    \   'ArgLead' : '',
                    \ }
    endif

    let ArgLead = tmp[len(tmp) - 1]
    call remove(tmp, len(tmp) - 1)

    if (has('win32') || has('win64'))
                \ && match(ArgLead, '^[a-z]:$') >= 0
        let ArgLead = ArgLead . '/'
    endif

    return {
                \   'prefix' : !empty(tmp) ? join(tmp, ' ') . ' ' : '',
                \   'ArgLead' : ArgLead,
                \ }
endfunction

function! s:restoreArgLead(ret, AL)
    let ret = []
    for item in a:ret
        call add(ret, a:AL.prefix . item)
    endfor
    return ret
endfunction

