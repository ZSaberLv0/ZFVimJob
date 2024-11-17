
" ============================================================
" ZFJobOutput(jobStatus, textList [, type(stdout/stderr)])
" jobStatus: {
"   'jobOption' : {
"     'outputTo' : {
"       'outputType' : 'statusline/logwin/popup',
"       'outputTypeExpand' : 'statusline/logwin/popup',
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
    let outputType = get(outputTo, 'outputType', '')

    let outputId = get(outputTo, 'outputId', '')
    if empty(outputId)
        let outputId = 'ZFJobOutput:' . s:outputIdNext()
    endif
    let a:jobStatus['jobImplData']['ZFJobOutput_outputId'] = outputId

    if exists('s:status[outputId]')
        call s:outputTypeDone_detach(outputId, s:status[outputId])

        let outputType = s:status[outputId]['outputTypeCur']
        if empty(outputType)
            let outputType = s:status[outputId]['outputTypeFixed']
            if empty(outputType)
                return
            endif
            let s:status[outputId]['outputTypeCur'] = outputType
            let s:status[outputId]['done'] = 0
            call s:impl_init(s:status[outputId], outputType)
        endif
    else
        if empty(outputType)
                    \ && empty(get(outputTo, 'outputExpand', ''))
                    \ && empty(get(outputTo, 'outputTypeSuccess', ''))
                    \ && empty(get(outputTo, 'outputTypeFail', ''))
            return
        endif
        let outputType = s:impl_fallback(outputType)
        let outputTypeExpand = s:impl_fallback(get(outputTo, 'outputTypeExpand', ''))
        let s:status[outputId] = {
                    \   'outputTo' : outputTo,
                    \   'expanded' : 0,
                    \   'expandedPrev' : 0,
                    \   'done' : 0,
                    \   'outputTypeCur' : outputType,
                    \   'outputTypeFixed' : outputType,
                    \   'outputTypeExpandFixed' : outputTypeExpand,
                    \   'outputTypeDoneFixed' : '',
                    \   'outputId' : outputId,
                    \   'jobStatus' : a:jobStatus,
                    \   'jobList' : [],
                    \   'autoCloseTimerId' : -1,
                    \   'outputTypeDoneDelayId' : -1,
                    \   'outputImplData' : {},
                    \ }
        if empty(outputType)
            return
        endif
        call s:impl_init(s:status[outputId], outputType)
    endif

    if index(s:status[outputId]['jobList'], a:jobStatus) < 0
        call add(s:status[outputId]['jobList'], a:jobStatus)
    endif
    call s:impl_output(s:status[outputId], outputType)

    call s:autoCloseStartCheck(outputId, 'outputAutoCleanup')
endfunction

function! ZFJobOutputExpand(...)
    let param = get(a:, 1, '')
    if type(param) == g:ZFJOB_T_STRING
        if param == ''
            for outputId in keys(s:status)
                call s:ZFJobOutputExpand(outputId)
            endfor
        else
            call s:ZFJobOutputExpand(param)
        endif
    elseif type(param) == g:ZFJOB_T_LIST
        for outputId in param
            call s:ZFJobOutputExpand(outputId)
        endfor
    endif
endfunction
function! s:ZFJobOutputExpand(outputId)
    call s:outputTypeDone_detach(a:outputId, s:status[a:outputId])

    let s:status[a:outputId]['expandedPrev'] = s:status[a:outputId]['expanded']
    let s:status[a:outputId]['expanded'] = 1 - s:status[a:outputId]['expanded']
    let outputTypeOld = s:status[a:outputId]['outputTypeCur']
    if s:status[a:outputId]['expanded']
        let outputTypeNew = s:status[a:outputId]['outputTypeExpandFixed']
        if empty(outputTypeNew)
            let outputTypeNew = outputTypeOld
        endif
    else
        let outputTypeNew = s:status[a:outputId]['outputTypeFixed']
    endif
    let s:status[a:outputId]['outputTypeCur'] = outputTypeNew

    let jobList = s:status[a:outputId]['jobList']
    if outputTypeOld != outputTypeNew
                \ && !empty(jobList)
        if !empty(outputTypeOld)
            call s:impl_cleanup(s:status[a:outputId], outputTypeOld)
        endif
        if s:status[a:outputId]['expanded']
            if !empty(outputTypeNew)
                call s:impl_init(s:status[a:outputId], outputTypeNew)
                call s:impl_output(s:status[a:outputId], outputTypeNew)
            endif
        else
            if !empty(outputTypeNew)
                call s:impl_init(s:status[a:outputId], outputTypeNew)
                call s:impl_output(s:status[a:outputId], outputTypeNew)
            endif
        endif
    endif
    call s:autoCloseStartCheck(a:outputId, 'outputManualCleanup')
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
"     'cleanup' : 'optional, function(outputStatus, jobStatus)',
"     'hide' : 'optional, function(outputStatus, jobStatus)',
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
"     'expanded' : 0/1,
"     'expandedPrev' : 0/1,
"     'done' : 0/1,
"     'outputTypeCur' : 'outputTypeFixed or outputTypeExpandFixed',
"     'outputTypeFixed' : 'fixed type after fallback check, maybe empty',
"     'outputTypeExpandFixed' : 'fixed type after fallback check, maybe empty',
"     'outputTypeDoneFixed' : 'fixed type after fallback check, valid only during auto close',
"     'outputId' : '',
"     'jobStatus' : {}, // jobStatus used to config the output
"     'jobList' : [ // all jobs still output
"       jobStatus,
"     ],
"     'autoCloseTimerId' : -1,
"     'outputTypeDoneDelayId' : -1,
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

function! s:impl_fallback(outputType)
    let outputType = a:outputType
    let impl = get(g:ZFJobOutputImpl, outputType, {})
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
    return outputType
endfunction
function! s:impl_init(outputStatus, outputType)
    let Fn = get(get(g:ZFJobOutputImpl, a:outputType, {}), 'init', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        call Fn(a:outputStatus, a:outputStatus['jobStatus'])
    endif
endfunction
function! s:impl_cleanup(outputStatus, outputType)
    let Fn = get(get(g:ZFJobOutputImpl, a:outputType, {}), 'cleanup', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        call Fn(a:outputStatus, a:outputStatus['jobStatus'])
    endif
endfunction
function! s:impl_hide(outputStatus, outputType)
    let Fn = get(get(g:ZFJobOutputImpl, a:outputType, {}), 'hide', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        call Fn(a:outputStatus, a:outputStatus['jobStatus'])
    endif
endfunction
function! s:impl_output(outputStatus, outputType, ...)
    let Fn = get(get(g:ZFJobOutputImpl, a:outputType, {}), 'output', 0)
    if type(Fn) == g:ZFJOB_T_FUNC
        let textListTmp = get(a:, 1, '')
        if type(textListTmp) == g:ZFJOB_T_LIST
            let textList = textListTmp
        elseif len(a:outputStatus['jobList']) == 1
            let textList = a:outputStatus['jobList'][0]['jobOutput']
        else
            let textList = []
            for jobStatus in a:outputStatus['jobList']
                call extend(textList, jobStatus['jobOutput'])
            endfor
        endif
        if !empty(textList)
            call Fn(a:outputStatus, a:outputStatus['jobStatus'], textList, 'stdout')
        endif
    endif
endfunction

function! s:autoCloseStartCheck(outputId, configKey)
    if a:configKey == 'outputAutoCleanup'
        let def = 10000
    else
        let def = 3000
    endif
    let timeout = get(s:status[a:outputId]['outputTo'], a:configKey, def)
    if timeout > 0
        call s:autoCloseStart(a:outputId, timeout)
    endif
endfunction

function! s:autoCloseStart(outputId, timeout)
    call s:autoCloseStop(a:outputId)
    if !ZFJobTimerAvailable() || a:timeout <= 0
        call ZFJobOutputImpl_autoCloseOnTimer(a:outputId)
        return
    endif
    let s:status[a:outputId]['autoCloseTimerId'] = ZFJobTimerStart(a:timeout, ZFJobFunc('ZFJobOutputImpl_autoCloseOnTimer', [a:outputId]))
endfunction

function! s:autoCloseStop(outputId)
    if !exists('s:status[a:outputId]') || s:status[a:outputId]['autoCloseTimerId'] == -1
        return
    endif
    call ZFJobTimerStop(s:status[a:outputId]['autoCloseTimerId'])
    let s:status[a:outputId]['autoCloseTimerId'] = -1
endfunction

function! ZFJobOutputImpl_autoCloseOnTimer(outputId, ...)
    let outputStatus = s:status[a:outputId]
    let outputStatus['autoCloseTimerId'] = -1

    if empty(outputStatus['jobList'])
        unlet s:status[a:outputId]
        call s:impl_cleanup(outputStatus, outputStatus['outputTypeCur'])
        let outputStatus['outputTypeCur'] = ''
    else
        call s:impl_hide(outputStatus, outputStatus['outputTypeCur'])
    endif

    call s:outputTypeDone_detach(a:outputId, outputStatus)
endfunction

" ============================================================
function! s:outputTypeDone_attach(outputId, jobStatus)
    if !exists('s:status[a:outputId]')
        return
    endif
    let outputStatus = s:status[a:outputId]
    call s:outputTypeDone_detach(a:outputId, outputStatus)

    let outputTypeDone = get(get(outputStatus, 'outputTo', {}), a:jobStatus['exitCode'] == '0' ? 'outputTypeSuccess' : 'outputTypeFail', '')
    let outputTypeDone = s:impl_fallback(outputTypeDone)
    if empty(outputTypeDone)
                \ || outputTypeDone == outputStatus['outputTypeCur']
        call s:autoCloseStartCheck(a:outputId, 'outputManualCleanup')
        return
    endif

    if empty(outputStatus['jobList'])
        call s:impl_cleanup(outputStatus, outputStatus['outputTypeCur'])
        let outputStatus['outputTypeCur'] = ''
    endif
    if !ZFJobTimerAvailable()
        call ZFJobOutputImpl_outputTypeDoneOnTimer(a:outputId, outputTypeDone, a:jobStatus)
        return
    endif
    let s:status[a:outputId]['outputTypeDoneDelayId'] = ZFJobTimerStart(200, ZFJobFunc('ZFJobOutputImpl_outputTypeDoneOnTimer', [a:outputId, outputTypeDone, a:jobStatus]))
endfunction
function! ZFJobOutputImpl_outputTypeDoneOnTimer(outputId, outputTypeDone, jobStatus, ...)
    let s:status[a:outputId]['outputTypeDoneDelayId'] = -1
    let outputStatus = s:status[a:outputId]
    let outputStatus['outputTypeDoneFixed'] = a:outputTypeDone
    let outputStatus['done'] = 1
    call s:impl_init(outputStatus, a:outputTypeDone)
    call s:impl_output(outputStatus, a:outputTypeDone, a:jobStatus['jobOutput'])
    call s:autoCloseStartCheck(a:outputId, 'outputManualCleanup')
endfunction
function! s:outputTypeDone_detach(outputId, outputStatus)
    if a:outputStatus['outputTypeDoneDelayId'] != -1
        call ZFJobTimerStop(a:outputStatus['outputTypeDoneDelayId'])
        let a:outputStatus['outputTypeDoneDelayId'] = -1
    endif
    if empty(a:outputStatus['outputTypeDoneFixed'])
        return
    endif
    call s:impl_cleanup(a:outputStatus, a:outputStatus['outputTypeDoneFixed'])
    let a:outputStatus['outputTypeDoneFixed'] = ''
endfunction

