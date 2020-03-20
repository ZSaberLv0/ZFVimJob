
function! s:fallbackCheck()
    if !has('timers')
        return 'statusline'
    else
        return ''
    endif
endfunction

function! s:outputInfoWrap(outputInfo, logId)
    return ZFStatuslineLogValue(ZFJobFuncCall(a:outputInfo, [ZFLogWinJobStatusGet(a:logId)]))
endfunction

function! s:outputInfoTimer(outputStatus, jobStatus, ...)
    call ZFLogWinRedrawStatusline(a:outputStatus['outputId'])
    call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
endfunction
function! s:outputInfoIntervalUpdate(outputStatus, jobStatus)
    if get(a:outputStatus['outputImplData'], 'outputInfoTaskId', -1) != -1
        call ZFJobTimerStop(a:outputStatus['outputImplData']['outputInfoTaskId'])
    endif
    let a:outputStatus['outputImplData']['outputInfoTaskId']
                \ = ZFJobTimerStart(a:outputStatus['outputImplData']['outputInfoInterval'], ZFJobFunc(function('s:outputInfoTimer'), [a:outputStatus, a:jobStatus]))
endfunction

function! s:init(outputStatus, jobStatus)
    let config = get(a:jobStatus['jobOption']['outputTo'], 'logwin', {})
    if empty(get(config, 'statusline', '')) && !empty(get(a:jobStatus['jobOption']['outputTo'], 'outputInfo', ''))
        let T_outputInfo = a:jobStatus['jobOption']['outputTo']['outputInfo']
        if type(T_outputInfo) == type('')
            let config = copy(config)
            let config['statusline'] = T_outputInfo
        elseif ZFJobFuncCallable(T_outputInfo)
            let config = copy(config)
            let config['statusline'] = ZFJobFunc(function('s:outputInfoWrap'), [T_outputInfo])

            let outputInfoInterval = get(a:jobStatus['jobOption']['outputTo'], 'outputInfoInterval', 0)
            if outputInfoInterval > 0 && has('timers')
                let a:outputStatus['outputImplData']['outputInfoInterval'] = outputInfoInterval
                call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
            endif
        endif
    endif
    call ZFLogWinConfig(a:outputStatus['outputId'], config)
endfunction

function! s:cleanup(outputStatus, jobStatus)
    if get(a:outputStatus['outputImplData'], 'outputInfoTaskId', -1) != -1
        call ZFJobTimerStop(a:outputStatus['outputImplData']['outputInfoTaskId'])
        unlet a:outputStatus['outputImplData']['outputInfoTaskId']
    endif
    if !get(get(a:outputStatus['outputTo'], 'logwin', {}), 'logwinNoCloseWhenFocused', 1) || !ZFLogWinIsFocused(a:outputStatus['outputId'])
        if get(get(a:outputStatus['outputTo'], 'logwin', {}), 'logwinAutoClosePreferHide', 0)
            call ZFLogWinHide(a:outputStatus['outputId'])
        else
            call ZFLogWinClose(a:outputStatus['outputId'])
        endif
        call ZFLogWinJobStatusSet(a:outputStatus['outputId'], {})
    endif
endfunction

function! s:attach(outputStatus, jobStatus)
    call ZFLogWinJobStatusSet(a:outputStatus['outputId'], a:jobStatus)
endfunction

function! s:detach(outputStatus, jobStatus)
    call ZFLogWinRedrawStatusline(a:outputStatus['outputId'])
endfunction

function! s:output(outputStatus, jobStatus, text, type)
    call ZFLogWinAdd(a:outputStatus['outputId'], a:text)
    call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
endfunction

if !exists('g:ZFJobOutputImpl')
    let g:ZFJobOutputImpl = {}
endif
let g:ZFJobOutputImpl['logwin'] = {
            \   'fallbackCheck' : function('s:fallbackCheck'),
            \   'init' : function('s:init'),
            \   'cleanup' : function('s:cleanup'),
            \   'attach' : function('s:attach'),
            \   'detach' : function('s:detach'),
            \   'output' : function('s:output'),
            \ }

