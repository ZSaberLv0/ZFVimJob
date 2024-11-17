
function! ZFJobOutput_logwin_fallbackCheck()
    if !ZFJobTimerAvailable()
        return 'statusline'
    else
        return ''
    endif
endfunction

function! ZFLogWinImpl_outputInfoWrap(outputInfo, logId)
    return ZFStatuslineLogValue(ZFJobFuncCall(a:outputInfo, [ZFLogWinJobStatusGet(a:logId)]))
endfunction

function! ZFLogWinImpl_outputInfoTimer(outputStatus, jobStatus, ...)
    call ZFLogWinRedrawStatusline(a:outputStatus['outputId'])
    call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
endfunction
function! s:outputInfoIntervalUpdate(outputStatus, jobStatus)
    if get(a:outputStatus['outputImplData'], 'outputInfoTaskId', -1) != -1
        call ZFJobTimerStop(a:outputStatus['outputImplData']['outputInfoTaskId'])
        let a:outputStatus['outputImplData']['outputInfoTaskId'] = -1
    endif
    if get(a:jobStatus['jobOption']['outputTo'], 'outputInfoInterval', 0) > 0 && ZFJobTimerAvailable()
        let a:outputStatus['outputImplData']['outputInfoTaskId']
                    \ = ZFJobTimerStart(a:jobStatus['jobOption']['outputTo']['outputInfoInterval'], ZFJobFunc('ZFLogWinImpl_outputInfoTimer', [a:outputStatus, a:jobStatus]))
    endif
endfunction

function! ZFJobOutput_logwin_init(outputStatus, jobStatus)
    let config = get(a:outputStatus['outputTo'], 'logwin', {})
    if empty(get(config, 'statusline', '')) && !empty(get(a:outputStatus['outputTo'], 'outputInfo', ''))
        let T_outputInfo = a:outputStatus['outputTo']['outputInfo']
        if type(T_outputInfo) == g:ZFJOB_T_STRING
            let config = copy(config)
            let config['statusline'] = T_outputInfo
        elseif ZFJobFuncCallable(T_outputInfo)
            let config = copy(config)
            let config['statusline'] = ZFJobFunc('ZFLogWinImpl_outputInfoWrap', [T_outputInfo])
            call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
        endif
    endif
    call ZFLogWinConfig(a:outputStatus['outputId'], config)
    call ZFLogWinJobStatusSet(a:outputStatus['outputId'], a:jobStatus)
    if a:outputStatus['expanded']
        call ZFLogWinFocus(a:outputStatus['outputId'])
    endif
endfunction

function! ZFJobOutput_logwin_cleanup(outputStatus, jobStatus)
    if get(a:outputStatus['outputImplData'], 'outputInfoTaskId', -1) != -1
        call ZFJobTimerStop(a:outputStatus['outputImplData']['outputInfoTaskId'])
        unlet a:outputStatus['outputImplData']['outputInfoTaskId']
    endif
    if !get(get(a:outputStatus['outputTo'], 'logwin', {}), 'logwinNoCloseWhenFocused', 1)
                \ || !ZFLogWinIsFocused(a:outputStatus['outputId'])
                \ || (a:outputStatus['expandedPrev'] && !a:outputStatus['expanded'])
        call ZFLogWinClose(a:outputStatus['outputId'])
        call ZFLogWinJobStatusSet(a:outputStatus['outputId'], {})
    endif
endfunction

function! ZFJobOutput_logwin_hide(outputStatus, jobStatus)
    if !ZFLogWinIsFocused(a:outputStatus['outputId'])
        call ZFLogWinHide(a:outputStatus['outputId'])
    endif
endfunction

function! ZFJobOutput_logwin_output(outputStatus, jobStatus, textList, type)
    if !ZFLogWinExist(a:outputStatus['outputId'])
        call ZFJobOutput_logwin_init(a:outputStatus, a:jobStatus)
    endif
    call ZFLogWinReplace(a:outputStatus['outputId'], a:textList)
    call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
endfunction

if !exists('g:ZFJobOutputImpl')
    let g:ZFJobOutputImpl = {}
endif
let g:ZFJobOutputImpl['logwin'] = {
            \   'fallbackCheck' : function('ZFJobOutput_logwin_fallbackCheck'),
            \   'init' : function('ZFJobOutput_logwin_init'),
            \   'cleanup' : function('ZFJobOutput_logwin_cleanup'),
            \   'hide' : function('ZFJobOutput_logwin_hide'),
            \   'output' : function('ZFJobOutput_logwin_output'),
            \ }

