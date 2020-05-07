
" ============================================================
" utils to support `function(xx, arglist)` low vim version
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
    elseif type(a:jobFunc) == type([])
        if len(a:jobFunc) == 1
            return string(a:jobFunc[0])
        else
            return string(a:jobFunc)
        endif
    else
        return string(a:jobFunc)
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
" timer
if !exists('s:jobTimerMap')
    " <jobTimerId, Fn_callback>
    let s:jobTimerMap = {}
endif
function! s:jobTimerCallback(timerId)
    if !exists('s:jobTimerMap[a:timerId]')
        return
    endif
    let Fn_callback = remove(s:jobTimerMap, a:timerId)
    call ZFJobFuncCall(Fn_callback, [a:timerId])
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

" ============================================================
" interval
if !exists('s:jobIntervalMap')
    " {
    "   'jobIntervalId' : {
    "     'timerId' : -1,
    "     'interval' : 123,
    "     'callback' : xxx,
    "     'count' : 'invoke count, first invoke is 1',
    "   },
    " }
    let s:jobIntervalMap = {}
endif
if !exists('s:jobIntervalId')
    let s:jobIntervalId = 0
endif
function! s:jobIntervalCallback(jobIntervalId, ...)
    if !exists('s:jobIntervalMap[a:jobIntervalId]')
        return
    endif
    let jobIntervalTask = s:jobIntervalMap[a:jobIntervalId]
    let jobIntervalTask['timerId'] = -1
    let jobIntervalTask['count'] += 1
    call ZFJobFuncCall(jobIntervalTask['callback'], [a:jobIntervalId, jobIntervalTask])
    if !exists('s:jobIntervalMap[a:jobIntervalId]')
        return
    endif
    let jobIntervalTask['timerId'] = ZFJobTimerStart(jobIntervalTask['interval'], ZFJobFunc(function('s:jobIntervalCallback'), [a:jobIntervalId]))
endfunction
" jobFunc: func(jobIntervalId, {
"   'count' : 'invoke count, first invoke is 1',
" })
function! ZFJobIntervalStart(interval, jobFunc)
    if !has('timers')
        echo 'ZFJobIntervalStart require has("timers")'
        return -1
    endif
    if a:interval <= 0
        echo 'invalid interval: ' . a:interval
        return -1
    endif
    while s:jobIntervalId <= 0 || exists('s:jobIntervalMap[s:jobIntervalId]')
        let s:jobIntervalId += 1
    endwhile
    let jobIntervalId = s:jobIntervalId
    let jobIntervalTask = {
                \   'timerId' : ZFJobTimerStart(a:interval, ZFJobFunc(function('s:jobIntervalCallback'), [jobIntervalId])),
                \   'interval' : a:interval,
                \   'callback' : a:jobFunc,
                \   'count' : 0,
                \ }
    if jobIntervalTask['timerId'] == -1
        return -1
    else
        let s:jobIntervalMap[jobIntervalId] = jobIntervalTask
        return jobIntervalId
    endif
endfunction
function! ZFJobIntervalStop(jobIntervalId)
    if !exists('s:jobIntervalMap[a:jobIntervalId]')
        return {}
    endif
    let jobIntervalTask = remove(s:jobIntervalMap, a:jobIntervalId)
    call ZFJobTimerStop(jobIntervalTask['timerId'])
    return jobIntervalTask
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

