function localAlcohol
    global BpodSystem
    global isEphysRig
    isEphysRig = true;
    S = struct;
    S.SoftCodeHandlerFunctionName = 'localAlcoholSoftCodeHandler';
    BpodSystem.SoftCodeHandlerFunction = S.SoftCodeHandlerFunctionName;
    
    
    %% setup pumps
    %Initialize microinjection pump on COM port (only for ephys rig)
    global microInjectionPump
    if isEphysRig
        S.COM_microInjectionPump = 'COM9';
        microInjectionPump = serial(S.COM_microInjectionPump);
        %Set all values in order to read values correctly
        set(microInjectionPump, 'Timeout', 60);
        set(microInjectionPump,'BaudRate', 9600);
        set(microInjectionPump, 'Parity', 'none');
        set(microInjectionPump, 'DataBits', 8);
        set(microInjectionPump, 'StopBits', 1);
        set(microInjectionPump, 'RequestToSend', 'off');
        %Open pump data stream
        fopen(microInjectionPump);
    end

    %Initialize sipper pump on COM port
    global sipperPump
    S.COM_sipperPump = 'COM4';
    sipperPump = serial(S.COM_sipperPump);
    %Set all values in order to read values correctly
    set(sipperPump, 'Timeout', 60);
    set(sipperPump,'BaudRate', 9600);
    set(sipperPump, 'Parity', 'none');
    set(sipperPump, 'DataBits', 8);
    set(sipperPump, 'StopBits', 1);
    set(sipperPump, 'RequestToSend', 'off');
    %Open pump data stream
    fopen(sipperPump);
    
    %% Obtain information from the user
    dlgtitle = 'Set Calibration Parameters';
    prompt = {...
        'Alcohol Concentration (Percent):',...
        'Drop Volume (uL):',...
        'Pump Volume Setting (uL):',...
        'Animal Weight (Grams):',...
        'Liquid Density (g/mL):',...
        };
    definput = {... % default values
        '20',... % alcohol concentration
        '4',... % drop volume
        '',... % pump volume
        '',... % animal weight
        '0.97',... % liquid density
        };
    dims = [1 60];
    answer = inputdlg(prompt,dlgtitle,dims,definput);
    alcCon = str2double(answer{1});
    dropVol = str2double(answer{2});
    pumpVolSetting = str2double(answer{3});
    animWeight = str2double(answer{4});
    liqDensity = str2double(answer{5});
    
    %% Experiment settings
    % Obtain information from the user
    dlgtitle = 'Set time limit for each stage of the experiment (minutes)';
    prompt = {...
        'Baseline:',...
        'Microinjection:',...
        'Post Injection',...
        'Sipper active:',...
        'Tail time:',...
        };
    
    definput = {... % default values
        '10',... % Baseline
        '2',... % Microinjection
        '10',...% Post Injection
        '15',... % Sipper active
        '10',... % Tail time
        };
    dims = [1 60];
    answer = inputdlg(prompt,dlgtitle,dims,definput);
    timeBaseline = str2double(answer{1});
    timeMicroinjection = str2double(answer{2});
    timePostInjection = str2double(answer{3});
    timeSipper = str2double(answer{4});
    timeTail = str2double(answer{5});
    
    %% Guide user for video setup
    % Tell the user to confirm the suction system is ready
    f = msgbox('Confirm the suction reservoir is empty and the suction valve is open.');
    uiwait(f)
    
    % Ask the user if they performed sipper alignment
    f = msgbox('Make sure to perform sipper alignment on video computer.');
    uiwait(f)
    
    mkdir([BpodSystem.Path.CurrentDataFile(1:(end - 4)),'Video']);
    videoDir = [BpodSystem.Path.CurrentDataFile(1:(end - 4)),'Video'];
    
    % Tell the user to start the video recording.
    f = msgbox(['Please start the video recording in FlyCapture2.',newline,newline,...
        'Follow these steps to start video recording.',newline,...
        'Open FlyCapture2.',newline,...
        'Click OK.',newline,...
        'Click File -> Capture Image or Video Sequence.',newline,...
        'The video filename should be ',videoDir,'\video.',newline,...
        'Recording mode should be set to Buffered.',newline,...
        'Click the videos tab, video recording type should be M-JPEG.',newline,...
        'Click use camera frame rate.',newline,...
        'Set AVI split size to 100.',newline,...
        'Set JPEG compression quality to 50%.']);
    uiwait(f)
    
    disp(' ')
    disp(' ')
    input('The protocol is ready to run. Press any key when you are ready to start the protocol.','s');
    
    
    %%
    totalTrials = 0;
    %% Experiment Stage 1: Baseline
    ticBaseline = tic();
    while (toc(ticBaseline)/60 < timeBaseline)
        timeLeft = timeBaseline*60 - toc(ticBaseline);
        disp(['Collecting Basline: ',num2str(timeLeft,3),' seconds left'])
    
        %--- Assemble state machine    
        sma = NewStateMachine();
        
        % State 1 - send 1 second alignment signal
        sma = AddState(sma, 'Name', 'TTL_ON', ...
            'Timer', 1,...
            'StateChangeConditions', {'Tup', 'TTL_OFF'},...
            'OutputActions', {'PWM2',255,'BNC1',255});
    
        % State 2 - Wait 1 second
        sma = AddState(sma, 'Name', 'TTL_OFF', ...
            'Timer', 1,...
            'StateChangeConditions', {'Tup', 'exit'},...
            'OutputActions', {});
    
        SendStateMatrix(sma); % Send state machine to the Bpod state machine device
        RawEvents = RunStateMatrix; % Run the trial and return events
    
        totalTrials = totalTrials + 1;
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Adds raw events to a human-readable data struct
        BpodSystem.Data.TrialSettings(totalTrials) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
    
        %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
        HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
        if BpodSystem.Status.BeingUsed == 0
            fclose(microInjectionPump);
            fclose(sipperPump);
            return
        end
    end
    
    %% Experiment Stage 2: Microinjection
    ticMicroinjection = tic();
    
    % run microinjection pump 
    sma = NewStateMachine();
    sma = AddState(sma, 'Name', 'MicroInject',...
        'Timer', 0.5,...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {'SoftCode', 3});
    SendStateMatrix(sma); % Send state machine to the Bpod state machine device
    RawEvents = RunStateMatrix; % Run the trial and return events
    totalTrials = totalTrials + 1;
    BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Adds raw events to a human-readable data struct
    BpodSystem.Data.TrialSettings(totalTrials) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
    SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file

    while (toc(ticMicroinjection)/60 < timeMicroinjection)
        timeLeft = timeMicroinjection*60 - toc(ticMicroinjection);
        disp(['Performing Microinjection: ',num2str(timeLeft,3),' seconds left'])
    
        %--- Assemble state machine    
        sma = NewStateMachine();
        
        % State 1 - send 1 second alignment signal
        sma = AddState(sma, 'Name', 'TTL_ON', ...
            'Timer', .5,...
            'StateChangeConditions', {'Tup', 'TTL_OFF'},...
            'OutputActions', {'PWM2',255,'BNC1',255});
    
        % State 2 - Wait 1 second
        sma = AddState(sma, 'Name', 'TTL_OFF', ...
            'Timer', 1,...
            'StateChangeConditions', {'Tup', 'exit'},...
            'OutputActions', {});
    
        SendStateMatrix(sma); % Send state machine to the Bpod state machine device
        RawEvents = RunStateMatrix; % Run the trial and return events
        totalTrials = totalTrials + 1;
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Adds raw events to a human-readable data struct
        BpodSystem.Data.TrialSettings(totalTrials) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
    
        %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
        HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
        if BpodSystem.Status.BeingUsed == 0
            fclose(microInjectionPump);
            fclose(sipperPump);
            return
        end
    end
    
    %% Experiment Stage 3: Post Injection
    ticPostInjection = tic();
    while (toc(ticPostInjection)/60 < timePostInjection)
        timeLeft = timePostInjection*60 - toc(ticPostInjection);
        disp(['Collecting Post Injection: ',num2str(timeLeft,3),' seconds left'])
    
        %--- Assemble state machine    
        sma = NewStateMachine();
        
        % State 1 - send 1 second alignment signal
        sma = AddState(sma, 'Name', 'TTL_ON', ...
            'Timer', 2,...
            'StateChangeConditions', {'Tup', 'TTL_OFF'},...
            'OutputActions', {'PWM2',255,'BNC1',255});
    
        % State 2 - Wait 1 second
        sma = AddState(sma, 'Name', 'TTL_OFF', ...
            'Timer', 1,...
            'StateChangeConditions', {'Tup', 'exit'},...
            'OutputActions', {});
    
       SendStateMatrix(sma); % Send state machine to the Bpod state machine device
       RawEvents = RunStateMatrix; % Run the trial and return events
       totalTrials = totalTrials + 1;
         BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Adds raw events to a human-readable data struct
      BpodSystem.Data.TrialSettings(totalTrials) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
      SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
    
       %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
        HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
        if BpodSystem.Status.BeingUsed == 0
            fclose(microInjectionPump);
            fclose(sipperPump);
            return
        end
    end
    
    %% Experiment Stage 4: Sipper time
    ticSipper = tic();
    nDropsDispensed = 0;
    PretrialDelayTime = 4;
    PostRewardDelay = 10;
    SipperClearTime = 1;
    while (toc(ticSipper)/60 < timeSipper)
        timeLeft = timeSipper*60 - toc(ticSipper);
        disp(['Sipper Trial: ',num2str(nDropsDispensed+1), ' ; seconds left: ',num2str(timeLeft,3)])
        
        %--- Assemble state machine    
        sma = NewStateMachine();
        
        % State 1
        % - Impose a brief pretrial delay, turn on IR LED to sync video
        sma = AddState(sma, 'Name', 'PretrialDelay', ...
            'Timer', PretrialDelayTime,...
            'StateChangeConditions', {'Tup', 'OpenFluidValve'},...
            'OutputActions', {'PWM2',255,'BNC1',255});
    
        % State 2
        % - Open the valve to deliver fluid
        sma = AddState(sma, 'Name', 'OpenFluidValve', ...
            'Timer', 0.1,...
            'StateChangeConditions', {'Tup', 'PostRewardDelay'},...
            'OutputActions', {'SoftCode', 2});
    
        nDropsDispensed = nDropsDispensed+1;
        
        % State 3
        % - Impose a delay to allow for consumption
        sma = AddState(sma, 'Name', 'PostRewardDelay', ...
            'Timer', PostRewardDelay,...
            'StateChangeConditions', {'Tup', 'ClearSipper'},...
            'OutputActions', {});
        
        % State 4
        % - Clear the sipper by suctioning off any fluid
        sma = AddState(sma, 'Name', 'ClearSipper', ...
            'Timer', SipperClearTime,...
            'StateChangeConditions', {'Tup', 'exit'},...
            'OutputActions', {'Valve2',1});
    
       SendStateMatrix(sma); % Send state machine to the Bpod state machine device
       RawEvents = RunStateMatrix; % Run the trial and return events
       totalTrials = totalTrials + 1;
         BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Adds raw events to a human-readable data struct
      BpodSystem.Data.TrialSettings(totalTrials) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
      SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
    
       %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
        HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
        if BpodSystem.Status.BeingUsed == 0
            fclose(microInjectionPump);
            fclose(sipperPump);
            return
        end
    end
    
    %% Experiment Stage 5: Tail time
    ticTail = tic();
    while (toc(ticTail)/60 < timeTail)
        timeLeft = timeTail*60 - toc(ticTail);
        disp(['Collecting Tail Time: ',num2str(timeLeft,3),' seconds left'])
    
        %--- Assemble state machine    
        sma = NewStateMachine();
        
        % State 1 - send 1 second alignment signal
        sma = AddState(sma, 'Name', 'TTL_ON', ...
            'Timer', 3,...
            'StateChangeConditions', {'Tup', 'TTL_OFF'},...
            'OutputActions', {'PWM2',255,'BNC1',255});
    
        % State 2 - Wait 1 second
        sma = AddState(sma, 'Name', 'TTL_OFF', ...
            'Timer', 1,...
            'StateChangeConditions', {'Tup', 'exit'},...
            'OutputActions', {});
    
       SendStateMatrix(sma); % Send state machine to the Bpod state machine device
       RawEvents = RunStateMatrix; % Run the trial and return events
        totalTrials = totalTrials + 1;
      BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Adds raw events to a human-readable data struct
      BpodSystem.Data.TrialSettings(totalTrials) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
      SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
    
       %--- This final block of code is necessary for the Bpod console's pause and stop buttons to work
        HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
        if BpodSystem.Status.BeingUsed == 0
            fclose(microInjectionPump);
            fclose(sipperPump);
            return
        end
    end
    
    %% Close pump I/O stream
    fclose(microInjectionPump);
    fclose(sipperPump);
    
    %% Stop video and record consumption volume
    % Tell the user to stop the video recording
    f = msgbox('Stop the video recording on the video recording computer!');
    uiwait(f)
    
    % Give the user the option to retake the sipper alignment photo
    f = msgbox('If you wish to retake the sipper alignment photo, do so now on the video recording computer.');
    uiwait(f)
    
    % Tell the user to remove the animal from the rig.
    f = msgbox('Remove the animal from the rig.');
    uiwait(f)
    
    % Ask the user to input the paper towel weights
    prompt = {'Dry Paper Towel Weight (g):','Wet Paper Towel Weight (g):'};
    dlgtitle = 'Suction Reservoir Paper Towel Weights';
    definput = {'',''};
    dims = [1 60];
    answer = inputdlg(prompt,dlgtitle,dims,definput);
    dryWeight = str2double(answer{1});
    wetWeight = str2double(answer{2});
    
    % Calculate various measurements of consumption and loss
    volDispensed = nDropsDispensed*dropVol/1000; % Volume in mL dispensed assuming each drop was dropVol microliters
    volCollected = (wetWeight - dryWeight)/liqDensity; % Volume in mL dispensed, but not consumed
    
    mkdir([BpodSystem.Path.CurrentDataFile(1:(end - 4)),'AdditionalData']);
    dataDir = [BpodSystem.Path.CurrentDataFile(1:(end - 4)),'AdditionalData',filesep];
    save([dataDir,'fluidMeasurements.mat'],'volDispensed','volCollected')
    
    % Display the estimates of the amount consumed
    msgbox(['Consumption (Fluid Lost Method): ',num2str((volDispensed - volCollected)*0.789*(alcCon/100)/(animWeight/1000),4),' g/kg']);
    disp('Protocol has ended. Please press stop in the Bpod GUI.')
end