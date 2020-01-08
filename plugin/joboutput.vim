
" ============================================================
" jobOption : {
"   'outputTo' : {
"     'outputType' : 'statusline/logwin/popup',
"     'outputCallback' : 'optional, function(jobStatus, text), return text',
"     'outputInfo' : 'optional, text or function(jobStatus) which return text',
"     'outputId' : 'if exists, use this fixed outputId',
"     'outputAutoCleanup' : 10000,
"     'outputManualCleanup' : 3000,
"
"     // extra config for actual impl
"     'statusline' : {...},
"     'logwin' : {
"       ...
"       'logwinNoCloseWhenFocused' : 1,
"       'logwinAutoClosePreferHide' : 0,
"     },
"     'popup' : {...},
"   },
" }

function! ZFJobOutput(jobStatus, text)
    if empty(a:jobStatus)
        return
    endif
    let outputType = get(get(a:jobStatus['jobOption'], 'outputTo', {}), 'outputType', '')
    if empty(outputType)
        return
    endif
    let impl = get(g:ZFJobOutputImpl, outputType, {})
    if empty(impl)
        return
    endif
    let outputTo = a:jobStatus['jobOption']['outputTo']
    if empty(get(outputTo, 'outputCallback', ''))
        let text = a:text
    else
        let text = ZFJobFuncCall(outputTo['outputCallback'], [a:jobStatus, a:text])
    endif

    let outputId = get(outputTo, 'outputId', '')
    if empty(outputId)
        let outputId = 'ZFJobOutput:' . s:outputIdNext()
    endif
    let a:jobStatus['jobImplData']['ZFJobOutput_outputId'] = outputId

    if !exists('s:status[outputId]')
        while 1
            let Fn = get(impl, 'fallbackCheck', 0)
            if type(Fn) != type(function('function'))
                break
            endif
            let outputTypeTmp = Fn()
            if empty(outputTypeTmp) || outputTypeTmp == outputType
                break
            endif
            let outputType = outputTypeTmp
            let impl = get(g:ZFJobOutputImpl, outputType, {})
            if empty(impl)
                return
            endif
        endwhile

        let s:status[outputId] = {
                    \   'outputTo' : outputTo,
                    \   'outputType' : outputType,
                    \   'outputId' : outputId,
                    \   'jobList' : [],
                    \   'autoCloseTimerId' : -1,
                    \   'outputImplData' : {},
                    \ }
        let Fn = get(impl, 'init', 0)
        if type(Fn) == type(function('function'))
            call Fn(outputId, s:status[outputId], a:jobStatus)
        endif
    endif

    if index(s:status[outputId]['jobList'], a:jobStatus) < 0
        call add(s:status[outputId]['jobList'], a:jobStatus)
        let Fn = get(impl, 'attach', 0)
        if type(Fn) == type(function('function'))
            call Fn(outputId, s:status[outputId], a:jobStatus)
        endif
    endif

    call s:autoCloseStop(outputId)

    let Fn = get(impl, 'output', 0)
    if type(Fn) == type(function('function'))
        call Fn(outputId, s:status[outputId], a:jobStatus, a:text)
    endif

    if get(s:status[outputId]['outputTo'], 'outputAutoCleanup', 10000) > 0
        call s:autoCloseStart(outputId, a:jobStatus, get(s:status[outputId]['outputTo'], 'outputAutoCleanup', 10000))
    endif
endfunction

function! ZFJobOutputCleanup(jobStatus)
    let outputId = get(a:jobStatus['jobImplData'], 'ZFJobOutput_outputId', '')
    if empty(outputId) || !exists('s:status[outputId]')
        return
    endif
    let index = index(s:status[outputId]['jobList'], a:jobStatus)
    if index < 0
        return
    endif
    call remove(s:status[outputId]['jobList'], index)

    let Fn = get(g:ZFJobOutputImpl[s:status[outputId]['outputType']], 'detach', 0)
    if type(Fn) == type(function('function'))
        call Fn(outputId, s:status[outputId], a:jobStatus)
    endif

    if !empty(s:status[outputId]['jobList'])
        if get(s:status[outputId]['outputTo'], 'outputAutoCleanup', 10000) > 0
            call s:autoCloseStart(outputId, a:jobStatus, get(s:status[outputId]['outputTo'], 'outputAutoCleanup', 10000))
        endif
    else
        call s:autoCloseStart(outputId, a:jobStatus, get(s:status[outputId]['outputTo'], 'outputManualCleanup', 3000))
    endif
endfunction

function! ZFJobOutputTaskMap()
    return s:status
endfunction

" {
"   'outputType' : {
"     'fallbackCheck' : 'optional, function() that return fallback outputType or empty to use current',
"     'init' : 'optional, function(outputId, outputStatus, jobStatus)',
"     'cleanup' : 'optional, function(outputId, outputStatus, jobStatus)',
"     'attach' : 'optional, function(outputId, outputStatus, jobStatus)',
"     'detach' : 'optional, function(outputId, outputStatus, jobStatus)',
"     'output' : 'optional, function(outputId, outputStatus, jobStatus, text)',
"   },
" }
"
" different output task may have same outputId,
" and each of them would have `attach` and `detach` called for once
if !exists('g:ZFJobOutputImpl')
    let g:ZFJobOutputImpl = {}
endif

" ============================================================

" {
"   outputId : { // first output jobStatus decide actual outputType and param
"     'outputTo' : {}, // jobStatus['jobOption']['outputTo']
"     'outputType' : '',
"     'outputId' : '',
"     'logwinNoCloseWhenFocused' : 1,
"     'logwinAutoClosePreferHide' : 0,
"     'jobList' : [
"       jobStatus,
"     ],
"     'autoCloseTimerId' : -1,
"     'outputImplData' : {}, // extra data holder for impl
"   },
" }
if !exists('s:status')
    let s:status = {}
endif
if !exists('s:outputIdCur')
    let s:outputIdCur = 0
endif
function! s:outputIdNext()
    let s:outputIdCur += 1
    while exists('s:status[s:outputIdCur]') || s:outputIdCur <= 0
        let s:outputIdCur += 1
    endwhile
    return s:outputIdCur
endfunction

function! s:autoCloseStart(outputId, jobStatus, timeout)
    call s:autoCloseStop(a:outputId)
    if !has('timers') || a:timeout <= 0
        call s:autoCloseOnTimer(a:outputId, a:jobStatus)
        return
    endif
    let s:status[a:outputId]['autoCloseTimerId'] = ZFJobTimerStart(a:timeout, ZFJobFunc(function('s:autoCloseOnTimer'), [a:outputId, a:jobStatus]))
endfunction

function! s:autoCloseStop(outputId)
    if !exists('s:status[a:outputId]') || s:status[a:outputId]['autoCloseTimerId'] == -1
        return
    endif
    call ZFJobTimerStop(s:status[a:outputId]['autoCloseTimerId'])
    let s:status[a:outputId]['autoCloseTimerId'] = -1
endfunction

function! s:autoCloseOnTimer(outputId, jobStatus, ...)
    if !exists('s:status[a:outputId]')
        return
    endif

    let outputStatus = s:status[a:outputId]
    let outputStatus['autoCloseTimerId'] = -1
    let index = index(outputStatus['jobList'], a:jobStatus)
    if index >= 0
        call remove(s:status[a:outputId]['jobList'], index)
    endif

    if empty(outputStatus['jobList'])
        unlet s:status[a:outputId]
    endif

    if index >= 0
        let Fn = get(g:ZFJobOutputImpl[outputStatus['outputType']], 'detach', 0)
        if type(Fn) == type(function('function'))
            call Fn(a:outputId, outputStatus, a:jobStatus)
        endif
    endif

    if empty(outputStatus['jobList'])
        let Fn = get(g:ZFJobOutputImpl[outputStatus['outputType']], 'cleanup', 0)
        if type(Fn) == type(function('function'))
            call Fn(a:outputId, outputStatus, a:jobStatus)
        endif
    endif
endfunction

