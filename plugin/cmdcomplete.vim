
function! ZFJobCmdComplete(ArgLead, CmdLine, CursorPos)
    let ret = ZFJobCmdComplete_env(a:ArgLead, a:CmdLine, a:CursorPos)
    if !empty(ret)
        return ret
    endif

    let paramIndex = ZFJobCmdComplete_paramIndex(a:ArgLead, a:CmdLine, a:CursorPos)
    if paramIndex == 0
        let ret = ZFJobCmdComplete_shellcmd(a:ArgLead, a:CmdLine, a:CursorPos)
        if empty(ret)
            let ret = ZFJobCmdComplete_file(a:ArgLead, a:CmdLine, a:CursorPos)
        endif
        return ret
    endif
    return ZFJobCmdComplete_file(a:ArgLead, a:CmdLine, a:CursorPos)
endfunction

" ============================================================
function! ZFJobCmdComplete_paramIndex(ArgLead, CmdLine, CursorPos)
    let cmd = substitute(a:CmdLine, '\\\\', '', 'g')
    let cmd = substitute(cmd, '\\.', '', 'g')
    let paramList = split(a:CmdLine, ' ')
    if empty(a:ArgLead)
        return len(paramList) - 1
    else
        return len(paramList) - 2
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

    if exists('*getcompletion')
        let m = {}
        for item in getcompletion('', 'environment')
            " [:\\\(\[\{].*
            let m[substitute(item, '[:\\([{].*', '', 'g')] = 1
        endfor
        let ret = keys(m)
    else
        let cmd = 'export'
        if has('win32')
            if executable('sh')
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
    if exists('*getcompletion')
        return s:fixPath(getcompletion(a:ArgLead, 'shellcmd'))
    else
        return []
    endif
endfunction

function! ZFJobCmdComplete_file(ArgLead, CmdLine, CursorPos)
    if exists('*getcompletion')
        return s:fixPath(getcompletion(a:ArgLead, 'file'))
    else
        return []
    endif
endfunction

function! s:fixPath(list)
    let ret = []
    for item in a:list
        let t = substitute(item, '\\', '/', 'g')
        let t = substitute(t, ' ', '\\ ', 'g')
        call add(ret, t)
    endfor
    return ret
endfunction

