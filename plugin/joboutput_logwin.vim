
function! s:fallbackCheck()
    if !has('timers')
        return 'statusline'
    else
        return ''
    endif
endfunction

function! s:init(outputId, outputStatus, jobStatus)
endfunction

function! s:attach(outputId, outputStatus, jobStatus)
    let outputTo = a:jobStatus['jobOption']['outputTo']
    let outputTaskId = a:outputStatus['outputTaskId']
    if a:outputStatus['outputTaskCount'] == 1
        call ZFLogWinConfig(outputTaskId, get(outputTo, 'logwin', {}))
    endif
endfunction

function! s:detach(outputId, outputStatus, jobStatus)
    let outputTaskId = a:outputStatus['outputTaskId']
    call ZFLogWinJobStatusSet(outputTaskId, a:jobStatus)
    call ZFLogWinRedraw(outputTaskId)
endfunction

function! s:cleanup(outputId, outputStatus, jobStatus)
    let outputTaskId = a:outputStatus['outputTaskId']
    if a:outputStatus['outputTaskCount'] == 0
        if !get(get(a:outputStatus['outputTo'], 'logwin', {}), 'logwinNoCloseWhenFocused', 1) || !ZFLogWinIsFocused(outputTaskId)
            if get(get(a:outputStatus['outputTo'], 'logwin', {}), 'logwinAutoClosePreferHide', 0)
                call ZFLogWinHide(outputTaskId)
            else
                call ZFLogWinClose(outputTaskId)
            endif
            call ZFLogWinJobStatusSet(outputTaskId, {})
        endif
    endif
endfunction

function! s:output(outputId, outputStatus, jobStatus, text)
    let outputTaskId = a:outputStatus['outputTaskId']
    call ZFLogWinJobStatusSet(outputTaskId, a:jobStatus)
    call ZFLogWinAdd(outputTaskId, a:text)
endfunction

if !exists('g:ZFJobOutputImpl')
    let g:ZFJobOutputImpl = {}
endif
let g:ZFJobOutputImpl['logwin'] = {
            \   'fallbackCheck' : function('s:fallbackCheck'),
            \   'init' : function('s:init'),
            \   'attach' : function('s:attach'),
            \   'detach' : function('s:detach'),
            \   'cleanup' : function('s:cleanup'),
            \   'output' : function('s:output'),
            \ }

