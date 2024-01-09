
function! ZFJobFallback(param)
    let paramType = type(a:param)
    if paramType == g:ZFJOB_T_STRING || paramType == g:ZFJOB_T_NUMBER || ZFJobFuncCallable(a:param)
        let jobOption = {
                    \   'jobCmd' : a:param,
                    \ }
    elseif paramType == g:ZFJOB_T_DICT
        let jobOption = copy(a:param)
    else
        echomsg '[ZFVimJob] unsupported param type: ' . paramType
        return -1
    endif

    let envSaved = ZFJobImplEnvUpdate(get(jobOption, 'jobEnv', {}))
    let ret = s:ZFJobFallback(jobOption)
    call ZFJobImplEnvRestore(envSaved)
    return ret
endfunction

function! s:ZFJobFallback(jobOption)
    let jobStatus = {
                \   'jobId' : 0,
                \   'jobOption' : a:jobOption,
                \   'jobOutput' : [],
                \   'exitCode' : '',
                \   'jobImplData' : copy(get(a:jobOption, 'jobImplData', {})),
                \ }

    call ZFJobLog(jobStatus, 'start (fallback): `' . ZFJobInfo(jobStatus) . '`')

    let T_jobCmd = get(a:jobOption, 'jobCmd', '')
    if type(T_jobCmd) == g:ZFJOB_T_STRING
        call ZFJobFuncCall(get(jobStatus['jobOption'], 'onEnter', ''), [jobStatus])

        let jobCmd = T_jobCmd
        if !empty(get(a:jobOption, 'jobCwd', ''))
            let jobCmd = 'cd "' . a:jobOption['jobCwd'] . '" && ' . jobCmd
        endif
        let result = system(jobCmd)
        let exitCode = '' . v:shell_error
    elseif type(T_jobCmd) == g:ZFJOB_T_NUMBER
        call ZFJobFuncCall(get(jobStatus['jobOption'], 'onEnter', ''), [jobStatus])

        " for fallback, sleep job has nothing to do
        let result = ''
        let exitCode = '0'
    elseif ZFJobFuncCallable(T_jobCmd)
        call ZFJobFuncCall(get(jobStatus['jobOption'], 'onEnter', ''), [jobStatus])

        if !empty(get(a:jobOption, 'jobCwd', ''))
            let cwdSaved = CygpathFix_absPath(getcwd())
            let jobCwd = CygpathFix_absPath(a:jobOption['jobCwd'])
            if cwdSaved != jobCwd
                execute 'cd ' . fnameescape(jobCwd)
            else
                let cwdSaved = ''
            endif
        else
            let cwdSaved = ''
        endif

        let result = ''
        let exitCode = '0'
        if exists('*execute')
            try
                let result = execute('let T_result = ZFJobFuncCall(T_jobCmd, [jobStatus])', 'silent')
            catch
                let result = v:exception
                let exitCode = '-1'
            endtry
        else
            try
                redir => result
                silent let T_result = ZFJobFuncCall(T_jobCmd, [jobStatus])
            catch
                let result = v:exception
            finally
                redir END
            endtry
        endif

        if !empty(cwdSaved)
            execute 'cd ' . fnameescape(cwdSaved)
        endif

        if exists('T_result') && type(T_result) == g:ZFJOB_T_DICT && exists("T_result['output']") && exists("T_result['exitCode']")
            let result = T_result['output']
            let exitCode = '' . T_result['exitCode']
        endif
    else
        call ZFJobLog(jobStatus, 'invalid jobCmd')
        return -1
    endif

    let jobEncoding = ZFJobImplSrcEncoding(jobStatus)
    if empty(jobEncoding)
        let jobOutput = result
    else
        let jobOutput = iconv(result, jobEncoding, &encoding)
    endif
    call ZFJobImpl_onOutput(jobStatus, split(jobOutput, "\n"), 'stdout')

    call ZFJobImpl_onExit(jobStatus, exitCode)
    if exitCode != '0'
        return -1
    else
        return 0
    endif
endfunction

