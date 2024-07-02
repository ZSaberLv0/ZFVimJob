
function! ZFJobOutput_statusline_fallbackCheck()
    return ''
endfunction

function! ZFJobOutput_statusline_init(outputStatus, jobStatus)
endfunction

function! ZFJobOutput_statusline_cleanup(outputStatus, jobStatus)
    call ZFStatuslineLogClear()
endfunction

function! ZFJobOutput_statusline_attach(outputStatus, jobStatus)
endfunction

function! ZFJobOutput_statusline_detach(outputStatus, jobStatus)
endfunction

function! ZFJobOutput_statusline_output(outputStatus, jobStatus, textList, type)
    let option = get(a:outputStatus['outputTo'], 'statusline', {})
    if !exists("option['timeout']")
        let option = copy(option)
        let option['timeout'] = 0
    endif
    call ZFStatuslineLog(a:textList[-1], option)
endfunction

if !exists('g:ZFJobOutputImpl')
    let g:ZFJobOutputImpl = {}
endif
let g:ZFJobOutputImpl['statusline'] = {
            \   'fallbackCheck' : function('ZFJobOutput_statusline_fallbackCheck'),
            \   'init' : function('ZFJobOutput_statusline_init'),
            \   'cleanup' : function('ZFJobOutput_statusline_cleanup'),
            \   'attach' : function('ZFJobOutput_statusline_attach'),
            \   'detach' : function('ZFJobOutput_statusline_detach'),
            \   'output' : function('ZFJobOutput_statusline_output'),
            \ }

