
" ============================================================
" utils to support `function(xx, arglist)` low vim version
function! ZFJobFuncImpl_funcWrap(cmd, ...)
    for cmd in a:cmd
        execute cmd
    endfor
endfunction

let s:jobFuncKey_func = 'ZF_fn'
let s:jobFuncKey_arglist = 'ZF_arg'

" NOTE: if you want to support vim 7.3, func must be placed in global scope
function! ZFJobFunc(func, ...)
    if empty(a:func)
        return {}
    endif

    let funcType = type(a:func)
    if funcType == g:ZFJOB_T_STRING
        let Fn_func = function(a:func)
        let argList = get(a:, 1, [])
        if empty(argList)
            return Fn_func
        endif
        return {
                    \   s:jobFuncKey_func : Fn_func,
                    \   s:jobFuncKey_arglist : argList,
                    \ }
    elseif funcType == g:ZFJOB_T_FUNC
        let argList = get(a:, 1, [])
        if empty(argList)
            return a:func
        endif
        return {
                    \   s:jobFuncKey_func : a:func,
                    \   s:jobFuncKey_arglist : argList,
                    \ }
    elseif funcType == g:ZFJOB_T_LIST
        " for line in a:func
        "     if type(line) != g:ZFJOB_T_STRING
        "         throw '[ZFJobFunc] unsupported func type: mixed array'
        "         return {}
        "     endif
        " endfor
        return ZFJobFunc('ZFJobFuncImpl_funcWrap', extend([a:func], get(a:, 1, [])))
    else
        throw '[ZFJobFunc] unsupported func type: ' . funcType
        return {}
    endif
endfunction

function! ZFJobFuncCall(func, ...)
    if empty(a:func)
        return 0
    endif

    let funcType = type(a:func)
    if funcType == g:ZFJOB_T_STRING
        return call(a:func, get(a:, 1, []))
    elseif funcType == g:ZFJOB_T_FUNC
        return call(a:func, get(a:, 1, []))
    elseif funcType == g:ZFJOB_T_DICT
        if !exists("a:func[s:jobFuncKey_func]") || !exists("a:func[s:jobFuncKey_arglist]")
            throw '[ZFJobFunc] unsupported func value'
            return 0
        endif
        return call(a:func[s:jobFuncKey_func], extend(copy(a:func[s:jobFuncKey_arglist]), get(a:, 1, [])))
    elseif funcType == g:ZFJOB_T_LIST
        return ZFJobFuncCall(ZFJobFunc(a:func), get(a:, 1, []))
    else
        throw '[ZFJobFunc] unsupported func type: ' . funcType
        return 0
    endif
endfunction

function! ZFJobFuncCallable(func)
    if empty(a:func)
        return 0
    endif

    let funcType = type(a:func)
    if funcType == g:ZFJOB_T_FUNC
        return 1
    elseif funcType == g:ZFJOB_T_DICT
        if !exists("a:func[s:jobFuncKey_func]") || !exists("a:func[s:jobFuncKey_arglist]")
            return 0
        endif
        return 1
    elseif funcType == g:ZFJOB_T_STRING
        try
            call function(a:func)
        catch
            " for logical safe, plain string is not treated as callable
            " wrap as ZFJobFunc should do the work
            return 0
        endtry
        return 1
    elseif funcType == g:ZFJOB_T_LIST
        for line in a:func
            if type(line) != g:ZFJOB_T_STRING
                return 0
            endif
        endfor
        return 1
    else
        return 0
    endif
endfunction

function! ZFJobFuncInfo(func)
    let funcType = type(a:func)
    if funcType == g:ZFJOB_T_STRING
        return a:func
    elseif funcType == g:ZFJOB_T_FUNC
        silent let info = s:jobFuncInfo(a:func)
        return substitute(info, '\n', '', 'g')
    elseif funcType == g:ZFJOB_T_DICT
        silent let info = s:jobFuncInfo(a:func[s:jobFuncKey_func])
        return substitute(info, '\n', '', 'g')
    elseif funcType == g:ZFJOB_T_LIST
        if len(a:func) == 1
            return string(a:func[0])
        else
            return substitute(string(a:func), '\n', ' ', 'g')
        endif
    else
        return string(a:func)
    endif
endfunction

if exists('*string')
    function! s:jobFuncInfo(func)
        return string(a:func)
    endfunction
elseif exists('*execute')
    function! s:jobFuncInfo(func)
        return execute('echo a:func')
    endfunction
else
    function! s:jobFuncInfo(func)
        try
            redir => info
            silent echo a:func
        finally
            redir END
        endtry
        return info
    endfunction
endif
function! s:funcScopeIsValid(funcString)
    return match(a:funcString, 's:\|w:\|t:\|b:') < 0
endfunction
function! s:funcFromString(funcString)
    if !s:funcScopeIsValid(a:funcString)
        throw '[ZFJobFunc] no `s:func` supported, use `function("s:func")` or put the func to global scopre instead, func: ' . a:funcString
    endif
    return function(a:funcString)
endfunction

" ============================================================
" arg parse
function! ZFJobCmdToList(jobCmd)
    let jobCmd = substitute(a:jobCmd, '\\ ', '_ZF_SPACE_ZF_', 'g')
    let jobCmd = substitute(jobCmd, '\\"', '_ZF_QUOTE_ZF_', 'g')
    let prevQuote = -1
    let i = len(jobCmd)
    while i > 0
        let i -= 1

        if jobCmd[i] == '"'
            if prevQuote == -1
                let prevQuote = i
            else
                let prevQuote = -1
            endif
            let jobCmd = strpart(jobCmd, 0, i)
                        \ . strpart(jobCmd, i + 1)
            continue
        endif

        if jobCmd[i] == ' ' && prevQuote != -1
            let jobCmd = strpart(jobCmd, 0, i)
                        \ . '_ZF_SPACE_ZF_'
                        \ . strpart(jobCmd, i + 1)
        endif
    endwhile
    let ret = []
    for item in split(jobCmd)
        let t = substitute(item, '_ZF_SPACE_ZF_', ' ', 'g')
        let t = substitute(t, '_ZF_QUOTE_ZF_', '"', 'g')
        call add(ret, t)
    endfor
    return ret
endfunction

" ============================================================
" running token
function! ZFJobRunningToken(jobStatus, ...)
    if len(get(a:jobStatus, 'exitCode', '')) != 0
        return get(a:, 1, ' ')
    endif
    let token = get(a:, 2, '-\|/')
    let a:jobStatus['jobImplData']['jobRunningTokenIndex']
                \ = (get(a:jobStatus['jobImplData'], 'jobRunningTokenIndex', -1) + 1) % len(token)
    return token[a:jobStatus['jobImplData']['jobRunningTokenIndex']]
endfunction

" ============================================================
" job option
function! ZFJobOptionExtend(option1, option2)
    for k2 in keys(a:option2)
        if !exists('a:option1[k2]') || type(a:option1[k2]) != g:ZFJOB_T_DICT
            let a:option1[k2] = a:option2[k2]
        else
            call ZFJobOptionExtend(a:option1[k2], a:option2[k2])
        endif
    endfor
    return a:option1
endfunction

" ============================================================
" others
function! CygpathFix_absPath(path)
    if len(a:path) <= 0|return ''|endif
    if !exists('g:CygpathFix_isCygwin')
        let g:CygpathFix_isCygwin = has('win32unix') && executable('cygpath')
    endif
    let path = fnamemodify(a:path, ':p')
    if !empty(path) && g:CygpathFix_isCygwin
        if 0 " cygpath is really slow
            let path = substitute(system('cygpath -m "' . path . '"'), '[\r\n]', '', 'g')
        else
            if match(path, '^/cygdrive/') >= 0
                let path = toupper(strpart(path, len('/cygdrive/'), 1)) . ':' . strpart(path, len('/cygdrive/') + 1)
            else
                if !exists('g:CygpathFix_cygwinPrefix')
                    let g:CygpathFix_cygwinPrefix = substitute(system('cygpath -m /'), '[\r\n]', '', 'g')
                endif
                let path = g:CygpathFix_cygwinPrefix . path
            endif
        endif
    endif
    return substitute(substitute(path, '\\', '/', 'g'), '\%(\/\)\@<!\/\+$', '', '') " (?<!\/)\/+$
endfunction

