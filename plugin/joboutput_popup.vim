
function! s:fallbackCheck()
    if !exists('*ZFPopupAvailable') || !ZFPopupAvailable()
        return 'logwin'
    else
        return ''
    endif
endfunction

function! s:init(outputId, outputStatus, jobStatus)
    let a:outputStatus['outputImplData']['popupid'] = ZFPopupCreate(get(a:jobStatus['jobOption']['outputTo'], 'popup', {}))
endfunction

function! s:cleanup(outputId, outputStatus, jobStatus)
    call ZFPopupClose(a:outputStatus['outputImplData']['popupid'])
endfunction

function! s:attach(outputId, outputStatus, jobStatus)
endfunction

function! s:detach(outputId, outputStatus, jobStatus)
endfunction

function! s:output(outputId, outputStatus, jobStatus, text)
    let popupid = a:outputStatus['outputImplData']['popupid']
    let content = ZFPopupContent(popupid)
    call add(content, a:text)
    call ZFPopupContent(popupid, content)
endfunction

if !exists('g:ZFJobOutputImpl')
    let g:ZFJobOutputImpl = {}
endif
let g:ZFJobOutputImpl['popup'] = {
            \   'fallbackCheck' : function('s:fallbackCheck'),
            \   'init' : function('s:init'),
            \   'cleanup' : function('s:cleanup'),
            \   'attach' : function('s:attach'),
            \   'detach' : function('s:detach'),
            \   'output' : function('s:output'),
            \ }

