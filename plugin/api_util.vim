
" ============================================================
" utils to support low vim version

function! s:ZFJobFuncWrap(cmd, ...)
    if type(a:cmd) == type('')
        execute a:cmd
    elseif type(a:cmd) == type([])
        for cmd in a:cmd
            execute cmd
        endfor
    endif
    if exists('ZFJobFuncRet')
        return ZFJobFuncRet
    endif
endfunction

let s:jobFuncKey_func = 'ZF_func'
let s:jobFuncKey_arglist = 'ZF_arglist'
function! ZFJobFunc(func, ...)
    if empty(a:func)
        return {}
    elseif type(a:func) == type('') || type(a:func) == type([])
        if type(a:func) == type([])
            for line in a:func
                if type(line) != type('')
                    throw '[ZFJobFunc] unsupported func type: mixed array'
                    return {}
                endif
            endfor
        endif
        return ZFJobFunc(function('s:ZFJobFuncWrap'), extend([a:func], get(a:, 1, [])))
    elseif type(a:func) == type(function('function'))
        let argList = get(a:, 1, [])
        if empty(argList)
            return a:func
        endif
        return {
                    \   s:jobFuncKey_func : a:func,
                    \   s:jobFuncKey_arglist : argList,
                    \ }
    else
        throw '[ZFJobFunc] unsupported func type: ' . type(a:func)
        return {}
    endif
endfunction

function! ZFJobFuncCall(func, argList)
    if empty(a:func)
        return 0
    elseif type(a:func) == type(function('function'))
        let Fn = a:func
        let argList = a:argList
        return call(a:func, a:argList)
    elseif type(a:func) == type('') || type(a:func) == type([])
        return ZFJobFuncCall(ZFJobFunc(a:func), a:argList)
    elseif type(a:func) == type({})
        if !exists("a:func[s:jobFuncKey_func]") || !exists("a:func[s:jobFuncKey_arglist]")
            throw '[ZFJobFunc] unsupported func value'
            return 0
        endif
        return call(a:func[s:jobFuncKey_func], extend(copy(a:func[s:jobFuncKey_arglist]), a:argList))
    else
        throw '[ZFJobFunc] unsupported func type: ' . type(a:func)
        return 0
    endif
endfunction

function! ZFJobFuncCallable(func)
    if empty(a:func)
        return 0
    elseif type(a:func) == type(function('function'))
        return 1
    elseif type(a:func) == type('')
        " for logical safe, string is not treated as callable
        " wrap as ZFJobFunc should do the work
        return 0
    elseif type(a:func) == type([])
        for line in a:func
            if type(line) != type('')
                return 0
            endif
        endfor
        return 1
    elseif type(a:func) == type({})
        if !exists("a:func[s:jobFuncKey_func]") || !exists("a:func[s:jobFuncKey_arglist]")
            return 0
        endif
        return 1
    else
        return 0
    endif
endfunction

function! ZFJobFuncInfo(jobFunc)
    if type(a:jobFunc) == type('')
        return a:jobFunc
    elseif type(a:jobFunc) == type(function('function'))
        silent let info = s:jobFuncInfo(a:jobFunc)
        return substitute(info, '\n', '', 'g')
    elseif type(a:jobFunc) == type({})
        silent let info = s:jobFuncInfo(a:jobFunc[s:jobFuncKey_func])
        return substitute(info, '\n', '', 'g')
    endif
endfunction

function! s:jobFuncInfo(jobFunc)
    redir => info
    echo a:jobFunc
    redir END
    return info
endfunction
function! s:funcScopeIsValid(funcString)
    return match(a:funcString, 's:\|w:\|t:\|b:') < 0
endfunction
function! s:funcFromString(funcString)
    if !s:funcScopeIsValid(a:funcString)
        throw '[ZFJobFunc] no `s:func` supported, use `function("s:func")` or put the func to global scopre instead, func: ' . a:funcString
    endif
    return function(a:funcString)
endfunction

if !exists('s:jobTimerMap')
    let s:jobTimerMap = {}
endif
function! s:jobTimerCallback(timerId)
    if !exists('s:jobTimerMap[a:timerId]')
        return
    endif
    let jobFunc = remove(s:jobTimerMap, a:timerId)
    call ZFJobFuncCall(jobFunc, [a:timerId])
endfunction
function! ZFJobTimerStart(delay, jobFunc)
    if !has('timers')
        call ZFJobFuncCall(a:jobFunc, [-1])
        return -1
    endif
    let timerId = timer_start(a:delay, function('s:jobTimerCallback'))
    if timerId == -1
        return -1
    endif
    let s:jobTimerMap[timerId] = a:jobFunc
    return timerId
endfunction
function! ZFJobTimerStop(timerId)
    if !exists('s:jobTimerMap[a:timerId]')
        return
    endif
    call remove(s:jobTimerMap, a:timerId)
    call timer_stop(a:timerId)
endfunction

