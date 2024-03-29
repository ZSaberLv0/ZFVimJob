
" ============================================================
" ZFJobOutput(jobStatus, textList [, type(stdout/stderr)])
" jobStatus: {
"   'jobOption' : {
"     'outputTo' : {
"       'outputType' : 'statusline/logwin/popup',
"       'outputTypeSuccess' : 'statusline/logwin/popup',
"       'outputTypeFail' : 'statusline/logwin/popup',
"       'outputId' : 'if exists, use this fixed outputId',
"       'outputInfo' : 'optional, text or function(jobStatus) which return text',
"       'outputInfoInterval' : 'if greater than 0, notify impl to update outputInfo with this interval',
"       'outputAutoCleanup' : 10000,
"       'outputManualCleanup' : 3000,
"
"       // extra config for actual impl
"       'statusline' : {...}, // see g:ZFStatuslineLog_defaultConfig
"       'logwin' : { // see g:ZFLogWin_defaultConfig
"         ...
"         'logwinNoCloseWhenFocused' : 1,
"         'logwinAutoClosePreferHide' : 0,
"       },
"       'popup' : {...}, // see g:ZFPopup_defaultConfig
"     },
"   }
" }
function! ZFJobOutput(jobStatus, content, ...)
    if empty(a:jobStatus)
        return
    endif
    let outputTo = get(a:jobStatus['jobOption'], 'outputTo', {})
    if empty(outputTo)
        return
    endif
    let outputType = get(outputTo, 'outputType', '')
    if empty(outputType)
                \ && empty(get(outputTo, 'outputTypeSuccess', ''))
                \ && empty(get(outputTo, 'outputTypeFail', ''))
        return
    endif
    let impl = empty(outputType) ? {} : get(g:ZFJobOutputImpl, outputType, {})

    let outputId = get(outputTo, 'outputId', '')
    if empty(outputId)
        let outputId = 'ZFJobOutput:' . s:outputIdNext()
    endif
    let a:jobStatus['jobImplData']['ZFJobOutput_outputId'] = outputId

    if exists('s:status[outputId]')
        if empty(s:status[outputId]['outputType'])
            let s:status[outputId]['outputType'] = outputType
            let impl = get(g:ZFJobOutputImpl, outputType, {})
            let Fn = get(impl, 'init', 0)
            if type(Fn) == g:ZFJOB_T_FUNC
                call Fn(s:status[outputId], a:jobStatus)
            endif
        else
            let outputType = s:status[outputId]['outputType']
            let impl = get(g:ZFJobOutputImpl, outputType, {})
        endif
        if empty(impl)
            return
        endif

        call s:outputTypeDone_detach(outputId, s:status[outputId], a:jobStatus)
    else
        while 1
            let Fn = get(impl, 'fallbackCheck', 0)
            if type(Fn) != g:ZFJOB_T_FUNC
                break
            endif
            let outputTypeTmp = Fn()
            if empty(outputTypeTmp) || outputTypeTmp == outputType
                break
            endif
            let outputType = outputTypeTmp
            let impl = get(g:ZFJobOutputImpl, outputType, {})
            if empty(impl)
                break
            endif
        endwhile

        let s:status[outputId] = {
                    \   'outputTo' : outputTo,
                    \   'outputType' : outputType,
                    \   'outputTypeDone' : '',
                    \   'outputId' : outputId,
                    \   'jobList' : [],
                    \   'autoCloseTimerId' : -1,
                    \   'outputImplData' : {},
                    \ }
        let Fn = get(impl, 'init', 0)
        if type(Fn) == g:ZFJOB_T_FUNC
            call Fn(s:status[outputId], a:jobStatus)
        endif
    endif

    call s:autoCloseStop(outputId)

    if index(s:status[outputId]['jobList'], a:jobStatus) < 0
        call add(s:status[outputId]['jobList'], a:jobStatus)
        let Fn = get(impl, 'attach', 0)
        if type(Fn) == g:ZFJOB_T_FUNC
            call Fn(s:status[outputId], a:jobStatus)
        endif
    endif

    let Fn = get(impl, 'output', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        if type(a:content) == g:ZFJOB_T_LIST
            if !empty(a:content)
                call Fn(s:status[outputId], a:jobStatus, a:content, get(a:, 1, 'stdout'))
            endif
        else
            call Fn(s:status[outputId], a:jobStatus, [a:content], get(a:, 1, 'stdout'))
        endif
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

    let Fn = get(get(g:ZFJobOutputImpl, s:status[outputId]['outputType'], {}), 'detach', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        call Fn(s:status[outputId], a:jobStatus)
    endif

    let Fn = get(get(g:ZFJobOutputImpl, s:status[outputId]['outputType'], {}), 'exit', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        call Fn(s:status[outputId], a:jobStatus)
    endif

    if !empty(s:status[outputId]['jobList'])
        if get(s:status[outputId]['outputTo'], 'outputAutoCleanup', 10000) > 0
            call s:autoCloseStart(outputId, a:jobStatus, get(s:status[outputId]['outputTo'], 'outputAutoCleanup', 10000))
        endif
    else
        call s:autoCloseStart(outputId, a:jobStatus, get(s:status[outputId]['outputTo'], 'outputManualCleanup', 3000))
    endif
    call s:outputTypeDone_attach(outputId, a:jobStatus)
endfunction

function! ZFJobOutputStatus(outputId)
    return get(s:status, a:outputId, {})
endfunction

function! ZFJobOutputTaskMap()
    return s:status
endfunction

" {
"   'outputType' : {
"     'fallbackCheck' : 'optional, function() that return fallback outputType or empty to use current',
"     'init' : 'optional, function(outputStatus, jobStatus)',
"     'exit' : 'optional, function(outputStatus, jobStatus)',
"     'cleanup' : 'optional, function(outputStatus, jobStatus)',
"     'attach' : 'optional, function(outputStatus, jobStatus)',
"     'detach' : 'optional, function(outputStatus, jobStatus)',
"     'output' : 'optional, function(outputStatus, jobStatus, textList, type)',
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
"     'outputType' : 'fixed type after fallback check, maybe empty',
"     'outputTypeDone' : 'fixed type after fallback check, valid only during auto close',
"     'outputId' : '',
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
    while 1
        let s:outputIdCur += 1
        if s:outputIdCur <= 0
            let s:outputIdCur = 1
        endif
        if exists('s:status[s:outputIdCur]')
            continue
        endif
        return s:outputIdCur
    endwhile
endfunction

function! s:autoCloseStart(outputId, jobStatus, timeout)
    call s:autoCloseStop(a:outputId)
    if !ZFJobTimerAvailable() || a:timeout <= 0
        call ZFJobOutputImpl_autoCloseOnTimer(a:outputId, a:jobStatus)
        return
    endif
    let s:status[a:outputId]['autoCloseTimerId'] = ZFJobTimerStart(a:timeout, ZFJobFunc('ZFJobOutputImpl_autoCloseOnTimer', [a:outputId, a:jobStatus]))
endfunction

function! s:autoCloseStop(outputId)
    if !exists('s:status[a:outputId]') || s:status[a:outputId]['autoCloseTimerId'] == -1
        return
    endif
    call ZFJobTimerStop(s:status[a:outputId]['autoCloseTimerId'])
    let s:status[a:outputId]['autoCloseTimerId'] = -1
endfunction

function! ZFJobOutputImpl_autoCloseOnTimer(outputId, jobStatus, ...)
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
        let Fn = get(get(g:ZFJobOutputImpl, outputStatus['outputType'], {}), 'detach', 0)
        if type(Fn) == g:ZFJOB_T_FUNC
            call Fn(outputStatus, a:jobStatus)
        endif
    endif

    if empty(outputStatus['jobList'])
        let Fn = get(get(g:ZFJobOutputImpl, outputStatus['outputType'], {}), 'cleanup', 0)
        if type(Fn) == g:ZFJOB_T_FUNC
            call Fn(outputStatus, a:jobStatus)
        endif
    endif

    call s:outputTypeDone_detach(a:outputId, outputStatus, a:jobStatus)
endfunction

" ============================================================
function! s:outputTypeDone_attach(outputId, jobStatus)
    if !exists('s:status[a:outputId]')
        return
    endif
    let outputStatus = s:status[a:outputId]
    let outputTypeDone = get(get(outputStatus, 'outputTo', {}), a:jobStatus['exitCode'] == '0' ? 'outputTypeSuccess' : 'outputTypeFail', '')
    if empty(outputTypeDone)
        return
    endif
    let impl = get(g:ZFJobOutputImpl, outputTypeDone, {})
    if empty(impl)
        return
    endif
    while 1
        let Fn = get(impl, 'fallbackCheck', 0)
        if type(Fn) != g:ZFJOB_T_FUNC
            break
        endif
        let outputTypeTmp = Fn()
        if empty(outputTypeTmp) || outputTypeTmp == outputTypeDone
            break
        endif
        let outputTypeDone = outputTypeTmp
        let impl = get(g:ZFJobOutputImpl, outputTypeDone, {})
        if empty(impl)
            return
        endif
    endwhile
    call s:outputTypeDone_detach(a:outputId, outputStatus, a:jobStatus)
    if outputTypeDone == outputStatus['outputType']
        return
    endif
    let outputStatus['outputTypeDone'] = outputTypeDone

    let index = index(outputStatus['jobList'], a:jobStatus)
    if index >= 0
        call remove(s:status[a:outputId]['jobList'], index)
        let Fn = get(get(g:ZFJobOutputImpl, outputStatus['outputType'], {}), 'detach', 0)
        if type(Fn) == g:ZFJOB_T_FUNC
            call Fn(outputStatus, a:jobStatus)
        endif
    endif
    if empty(outputStatus['jobList'])
        let Fn = get(get(g:ZFJobOutputImpl, outputStatus['outputType'], {}), 'cleanup', 0)
        if type(Fn) == g:ZFJOB_T_FUNC
            call Fn(outputStatus, a:jobStatus)
        endif
        let outputStatus['outputType'] = ''
    endif

    let Fn = get(g:ZFJobOutputImpl[outputTypeDone], 'init', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        call Fn(outputStatus, a:jobStatus)
    endif
    let Fn = get(g:ZFJobOutputImpl[outputTypeDone], 'attach', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        call Fn(outputStatus, a:jobStatus)
    endif
    let Fn = get(g:ZFJobOutputImpl[outputTypeDone], 'output', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        call Fn(outputStatus, a:jobStatus, a:jobStatus['jobOutput'], 'stdout')
    endif
endfunction
function! s:outputTypeDone_detach(outputId, outputStatus, jobStatus)
    if empty(a:outputStatus['outputTypeDone'])
        return
    endif
    let Fn = get(g:ZFJobOutputImpl[a:outputStatus['outputTypeDone']], 'detach', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        call Fn(a:outputStatus, a:jobStatus)
    endif
    let Fn = get(g:ZFJobOutputImpl[a:outputStatus['outputTypeDone']], 'cleanup', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        call Fn(a:outputStatus, a:jobStatus)
    endif
    let a:outputStatus['outputTypeDone'] = ''
endfunction

