classdef BehaviorBox12 < hgsetget
    % ---------------------------------------------------------------------
    % BehaviorBox
    % Han Lab
    % 7/11/2011
    % Mark Bucklin
    %
    %
    %for SS2 and add laser control
    %JZ 11/20/11
    % Modified to stop the laser ater punishment and the default laser is
    % off ( on the laser back, TTL+ )
    %JZ 12/9
    
%     Change to burst model for 33120A
%         from stimOn until touch
%         
%         
%         JZ 12/17/2011
%Box12 is giving laser on every reversal after 2 correct trials  JZ 5/17/2012 

        
    % ---------------------------------------------------------------------
    %
    % This class defines experimental parameters (timing, stimulus, etc.)
    % and runs the experiment
    %  
    % See Also TOUCHINTERFACE RECTANGLE TOUCHDISPLAY NIDAQINTERFACE
    
    
    
    
    
    properties
        stimOnTime
        interTrialInterval
        pauseTime
        rewardTime
        punishTime
        laserTime
        stimSet % cell array of scalar vectors with stimulus numbers
        correctResponse
        stimOrder % 'random' or 'sequential'
        toneFrequency
        toneDuration
        toneVolume
        default       
        mouseID
        ExperimentID
    end
    
    properties (SetAccess = protected)
        dataSummaryObj
        touchDisplayObj % TouchDisplay
        nidaqObj % NiDaqInterface
        speakerObj % Speaker
        nosePokeListener % Listens for nose-poke On/Off events from the reward chamber
        touchDisplayListener % Listens for any touch to the touch screen
        stimPokeListener % Listens for pokes to the stimulus (rectangle) while onscreen
        falsePokeListener % Listens for pokes to a stimulus while it is offscreen
        punishmentTimer
        laserTimer% 11/20/11
        interTrialTimer
        stimulusTimer
        pauseTimer
        trialPhase % 'stopped' 'wait4poke' 'stimulus' 'reward' 'punish' 'intertrial'
        trialPhaseNum
        currentStim % scalar vector with the stimulus numbers being presented
        currentStimNumber
        mouseResponse
        isready
        stage
        counterError% for 7 out 8 criterion
        counterP% counterP(revious) for 7 out 8 criterion
        counterCurrent% for 7 out 8 criterion
        ReversalN
    end
    
    properties (Hidden)        
        shouldContinue % true if the next trial should start at the end of the ITI (rather than wait for poke)
    end
    
    
    events
        TrialStart
        StimOn
        StimOff
        Reward % Correct
        Punish % Incorrect
        NoResponse % Abort/No-Attempt
        Wait4Poke
        Reversal  % reverse when 7 out of 8 correct
        LaserOff
        LaserOn
    end
    
    
    
    
    methods % Initialization
        function obj = BehaviorBox12(varargin)
            % Assign input arguments to object properties
            if nargin > 1
                for k = 1:2:length(varargin)
                    obj.(varargin{k}) = varargin{k+1};
                end
            end
            % Define Defaults
            obj.default = struct(...
                'stimOnTime',2000,...% test for just 20 sec 12/9
                'interTrialInterval',10,...%
                'pauseTime',0.5,...
                'rewardTime',.2,...% reward time increased from .2 to .4. so mice get more water 
                'punishTime',10,...%
                'laserTime',2000,...% add laserTime so long that it will stop only after the touch 12/17/11
                'stimSet',{{[3 5];[5 3]}},...% design for trainging widnows in [3 5]
                'correctResponse',{{3;5}},...
                'stimOrder','currentStimNumber',...
                'toneFrequency',1100,...
                'toneDuration',.5,...
                'toneVolume',.5);
            obj.isready = false;
            obj.shouldContinue = false;
            obj.trialPhase = 'stopped';
        end
        function setup(obj)
            % Fill in Defaults
            props = fields(obj.default);
            for n=1:length(props)
                thisprop = sprintf('%s',props{n});
                if isempty(obj.(thisprop))
                    obj.(thisprop) = obj.default.(thisprop);
                end
            end
            % Construct Touch-Display and Daq Interfaces
            obj.touchDisplayObj = TouchDisplay;
            setup(obj.touchDisplayObj);
            obj.nidaqObj = NiDaqInterface;
            setup(obj.nidaqObj)
            obj.speakerObj = Speaker;
            setup(obj.speakerObj);
            % Listen for Events            
            obj.nosePokeListener = event.listener.empty(2,0);
            obj.touchDisplayListener = event.listener.empty(1,0);
            obj.stimPokeListener = event.listener.empty(7,0);
            obj.falsePokeListener = event.listener.empty(7,0);
            obj.nosePokeListener(1) = addlistener(...
                obj.nidaqObj,...
                'NosePokeOn',...
                @(src,evnt)nosePokeFcn(obj,src,evnt));
            obj.nosePokeListener(2) = addlistener(...
                obj.nidaqObj,...
                'NosePokeOff',...
                @(src,evnt)nosePokeFcn(obj,src,evnt));
            obj.touchDisplayListener = addlistener(...
                obj.touchDisplayObj,...
                'ScreenPoke',...
                @(src,evnt)screenPokeFcn(obj,src,evnt));
            for n = 1:obj.touchDisplayObj.numStimuli
                obj.stimPokeListener(n) = addlistener(...
                    obj.touchDisplayObj.stimuli(n),...
                    'StimPoke',...
                    @(src,evnt)stimPokeFcn(obj,src,evnt));
                obj.falsePokeListener(n) = addlistener(...
                    obj.touchDisplayObj.stimuli(n),...
                    'FalsePoke',...
                    @(src,evnt)falsePokeFcn(obj,src,evnt));
            end
            % Construct Timer Objects

            % Construct a Data Summary Object
            obj.stage = 'Stage12';         
            % Ready
            obj.isready = true;          
            obj.rewardPump('on') % works in reverse. so ON == OFF
            obj.houseLight('on') % works in reverse. so ON == OFF
            obj.laser('off') % works in reverse. so ON == OFF? 11/20/11
        end
    end
    methods % User Control Functions
        function start(obj)    
            % Construct Timer Objects
            obj.stimulusTimer = timer(...
                'StartFcn',@(src,evnt)startStimFcn(obj,src,evnt),...
                'StartDelay',obj.stimOnTime,...
                'TimerFcn',@(src,evnt)endStimFcn(obj,src,evnt),...
                'StopFcn',@(src,evnt)stopStimFcn(obj,src,evnt),...
                'TasksToExecute',1);
            obj.interTrialTimer = timer(...
                'StartFcn',@(src,evnt)startInterTrialFcn(obj,src,evnt),...
                'StartDelay',obj.interTrialInterval,...
                'TimerFcn',@(src,evnt)endInterTrialFcn(obj,src,evnt),...
                'TasksToExecute',1);
            obj.punishmentTimer = timer(...
                'StartFcn',@(src,evnt)startPunishFcn(obj,src,evnt),...
                'StartDelay',obj.punishTime,...
                'TimerFcn',@(src,evnt)endPunishFcn(obj,src,evnt),...
                'TasksToExecute',1);
            obj.pauseTimer = timer(...
                'StartFcn',@(src,evnt)startPauseFcn(obj,src,evnt),...
                'StartDelay',obj.pauseTime,...
                'TimerFcn',@(src,evnt)endPauseFcn(obj,src,evnt),...
                'TasksToExecute',1);
             obj.laserTimer = timer(...% laser timer setting. either end when time is up, or stop when call the stop function 11/20/11
                'StartFcn',@(src,evnt)startLaserFcn(obj,src,evnt),...
                'StartDelay',obj.laserTime,...
                'TimerFcn',@(src,evnt)endLaserFcn(obj,src,evnt),...
                'StopFcn',@(src,evnt)stopLaserFcn(obj,src,evnt),...
                'TasksToExecute',2);
            fprintf('\n\n')
             obj.ExperimentID = input('Please enter ExperimentID:','s');
            obj.mouseID = input('Please enter mouse ID#:','s');
            obj.currentStimNumber = input('Please enter the rewarded stimNumber (1 for window3;2 for window5):');% input the starting rewarded window JZ 10/11/11
            obj.rewardPump('on') % works in reverse. so ON == OFF
            obj.currentStim = obj.stimSet{obj.currentStimNumber};
            obj.touchDisplayObj.prepareNextStimulus(obj.currentStim);
            obj.trialPhase = 'wait4poke';
            fprintf('\n\n\n\nStage 12    %s    Mouse#: %s\n',...
                datestr(now,'mm/dd/yyyy'),obj.mouseID)
            fprintf('%s',datestr(now,'HH:MM:SS'))
            notify(obj,'TrialStart');
            obj.rewardLight('on')
            obj.houseLight('on') % works in reverse. so ON == OFF
            obj.laser('off') % works in reverse. so ON == OFF? 11/20/11
            obj.dataSummaryObj = DataSummary(obj,obj.stage,obj.mouseID,obj.ExperimentID);
            obj.counterError = 0;% for 7 out 8 criterion
            obj.counterP = 0;
            obj.counterCurrent = 0;
            obj.ReversalN =0;% JZ 12/20
            %obj.countset = [0 0];% for 7 out 8 criterion
        end
        function stop(obj)            
            obj.trialPhase = 'stopped';
            obj.rewardLight('off')
            obj.houseLight('on') % works in reverse. so ON == OFF
            obj.rewardPump('on') % works in reverse. so ON == OFF
            obj.laser('off') % works in reverse. so ON == OFF? 11/20/11
            delete(obj.stimulusTimer);
            delete(obj.interTrialTimer);   
            delete(obj.punishmentTimer);
%             delete(obj.laserTimer);%11/20/11
            obj.touchDisplayObj.hideStimulus();
        end
    end
    methods % Hardware Control Functions
        function houseLight(obj,varargin)
            if obj.isready
                if nargin<2
                    obj.nidaqObj.digitalSwitch('houselight');
                else
                    obj.nidaqObj.digitalSwitch('houselight',varargin{1});
                end
            end
        end
        function rewardLight(obj,varargin)
            if obj.isready
                if nargin<2
                    obj.nidaqObj.digitalSwitch('rewardlight');
                else
                    obj.nidaqObj.digitalSwitch('rewardlight',varargin{1});
                end
            end
        end
        function rewardPump(obj,varargin)
            if obj.isready
                if nargin<2
                    obj.nidaqObj.digitalSwitch('pump');
                else
                    obj.nidaqObj.digitalSwitch('pump',varargin{1});
                end
            end
        end
        function laser(obj,varargin)% 11/20/11
            if obj.isready
                if nargin<2
                    obj.nidaqObj.digitalSwitch('laser');
                else
                    obj.nidaqObj.digitalSwitch('laser',varargin{1});
                end
            end
        end
        function giveReward(obj,varargin)
            if obj.isready
                if nargin<2
                    t = obj.rewardTime;
                else
                    t = varargin{1};
                end
                obj.nidaqObj.reward(t);
                obj.playSound(1100);
            end
            obj.rewardPump('off') % works in reverse. so ON == OFF
        end
        function givePunishment(obj,varargin)
            if obj.isready
                if nargin<2
                    t = obj.punishTime;
                else
                    t = varargin{1};
                end
                obj.nidaqObj.punish(t);         
                obj.playSound(200);% a different sound indicating wrong
            end
            obj.houseLight('off') % works in reverse. so ON == OFF
            start(obj.punishmentTimer);%% here start the punishment timer!  JZ 10/11/11
            
            
        end
        function playSound(obj,varargin)
            % this function plays a sound at the frequency, duration, and
            % volume specified the in the BehaviorBox properties. The user
            % can alternatively pass a frequency in Hz to play
            if nargin>1
                frequency = varargin{1};
            else
                frequency = obj.toneFrequency;
            end
            if nargin>2
                duration = varargin{2};
            else
                duration = obj.toneDuration;
            end
            if nargin>3
                volume = varargin{3};
            else
                volume = obj.toneVolume;
            end
            if obj.isready
                obj.speakerObj.playTone(...
                    frequency,...
                    duration,...
                    volume);
            end
        end
    end
    methods % Event Response Functions
        function nosePokeFcn(obj,src,evnt)
            if strcmp(evnt.EventName,'NosePokeOff')
                    switch obj.trialPhase
                        case 'wait4poke' % trial initiated
                            obj.rewardLight('off')
                            obj.shouldContinue = true;
                            start(obj.stimulusTimer);
                           if obj.counterCurrent + obj.counterP >= 2 %control the laser burst only at the time of 2 more correct  JZ 2/27/12 
                            
                            start(obj.laserTimer);% 11/20/11
                           end
                        case 'stimulus'                            
                        case 'reward'
                            obj.shouldContinue = true;
                        case 'punish'
                            obj.houseLight('off')%%? JZ 10/11/11
                            obj.shouldContinue = true;
                            start(obj.punishmentTimer);%%?  JZ 10/11/11
                        case 'intertrial' % poking before cue to initiate
                            % Restart InterTrial Timer
                            %stop(obj.interTrialTimer);
                            %start(obj.interTrialTimer);
                            obj.shouldContinue = true;
                    end
                    
            end
        end
        function screenPokeFcn(obj,src,evnt)
            if obj.isready
                
            end
        end
        function stimPokeFcn(obj,src,evnt)
            % src = Rectangle object that was poked
            if strcmp('stimulus',obj.trialPhase)
                obj.mouseResponse = eval(src.name(end)); % e.g. name = 'rectangle5' -> mouseResponse = 5
                fprintf('\b %d \n',obj.mouseResponse)
                stop(obj.stimulusTimer);
                
            end
            if obj.counterCurrent + obj.counterP >= 2 %control the laser burst only at the time of 2 more correct JZ 2/27/12 
               stop(obj.laserTimer); % 11/20/11 stop laser
            end
        end
        function falsePokeFcn(obj,src,evnt)
            if obj.isready
                if strcmp('stimulus',obj.trialPhase)
                    obj.mouseResponse = eval(src.name(end)); % e.g. name = 'rectangle5' -> mouseResponse = 5
                    fprintf('\b %d \n',obj.mouseResponse)
                     stop(obj.stimulusTimer);% i leave it unaltered, assuming is fine JZ 12/20
                    %obj.trialPhaseNum = 0;     % to set the trail as failed JZ
                 if obj.counterCurrent + obj.counterP >= 2 %control the laser burst only at the time of 2 more correct JZ 2/27/12
                    stop(obj.laserTimer); % 11/20/11 stop laser
                 end
                end
            end
        end
    end
    methods % Time-Point Functions
        function startStimFcn(obj,src,evnt)
            obj.touchDisplayObj.showStimulus()
            obj.playSound(300,0.3)%% sound when mouse initialze the trial JZ 9/20/11 %obj.playSound(2000);
            fprintf('%s',datestr(now,'HH:MM:SS'))
            notify(obj,'StimOn');
            obj.trialPhase = 'stimulus';
            
        end
        function endStimFcn(obj,src,evnt)
            % This function is called if the stimulus presentation period
            % is reached without a response from the mouse
            obj.mouseResponse = [];
            fprintf('%s',datestr(now,'HH:MM:SS'))
            notify(obj,'NoResponse')
            %obj.givePunishment()
            obj.trialPhase = 'NoResponse';
            %obj.trialPhaseNum = 0;
            obj.shouldContinue = true;%%? JZ
            %start(obj.punishmentTimer);
        end
        function stopStimFcn(obj,src,evnt)
            % This function is called when the stimulusTimer is stopped,
            % either because it has reached the time limit (after
            % endStimFcn) or because stop(obj.stimulusTimer) was called
            obj.touchDisplayObj.hideStimulus()
            %fprintf('%s',datestr(now,'HH:MM:SS'))
            %notify(obj,'StimOff');
%             stop(obj.laserTimer); % JZ 12/9
            if ~isempty(obj.mouseResponse)
                % Mouse Responded
                if obj.mouseResponse == obj.correctResponse{obj.currentStimNumber}
                    % Reward Mouse
                    obj.playSound(500,0.25);%? JZ
                    start(obj.pauseTimer);  
                else
                    % Punish Mouse
                    obj.givePunishment()
                    fprintf('%s',datestr(now,'HH:MM:SS'))
                    notify(obj,'Punish');
                    obj.trialPhase = 'Punish';
                   
                    
                    obj.shouldContinue = true;
                    
                end
            else
                % Mouse didn't respond
                obj.shouldContinue = true;
                
                %%% Box 5 contains many lines here JZ 10/5/11
            end
        end
        function startLaserFcn(obj,src,evnt)
           obj.laser('on') ;% 11/20/11
           notify(obj,'LaserOn'); %JZ 12/9
        end
        function endLaserFcn(obj,src,evnt)
            % This function is called if the stimulus presentation period
            % is reached without a response from the mouse
%             obj.laser('on') ;% 11/20/11
%             
%              fprintf('%s',datestr(now,'HH:MM:SS'))% only end laser show the time JZ 12/9
%              notify (obj,'LaserOff')
            
        end
        function stopLaserFcn(obj,src,evnt)
            % This function is called when the laserTimer is stopped,
            % either because it has reached the time limit (after
            % endlaserFcn) or because stop(obj.laserTimer) was called
            obj.laser('off');% 11/20/11
            fprintf('%s',datestr(now,'HH:MM:SS'))
            notify (obj,'LaserOff')
        end
        function startInterTrialFcn(obj,src,evnt)%% COunting the 7 out of 8 criterion?  JZ 10/5/11
            obj.counterCurrent = obj.counterCurrent + 1;
            switch obj.counterError
                
%             elseif obj.trialPhaseNum == 0  % Actually, this one never excuted because wrong poke go to Falspoke only and never connect with ITI JZ10/10/11
%                 obj.counter(2) = obj.counter(2) + 1;
                case 0
            
                 if obj.counterCurrent== 7  % 7 out of 8 criterion
                        obj.counterError = 0;% for 7 out 8 criterion
                        obj.counterP = 0;
                        obj.counterCurrent = 0;
                        notify(obj,'Reversal');  % notify data summary JZ10/10/11
                        %obj.countset(1) = obj.countset(1) + 1;
                        obj.ReversalN = obj.ReversalN+1; %count reversal
                        switch obj.currentStimNumber%% switch the rewarded window after reversal! JZ 10/11/2011
                            case 1
                            obj.default.correctresponse = {[5]};
                            obj.currentStimNumber = 2;
                            obj.currentStim = obj.stimSet{obj.currentStimNumber};
                            obj.touchDisplayObj.prepareNextStimulus(obj.currentStim);
                            case 2
                            obj.default.correctresponse = {[3]};
                            obj.currentStimNumber = 1;
                            obj.currentStim = obj.stimSet{obj.currentStimNumber};
                            obj.touchDisplayObj.prepareNextStimulus(obj.currentStim);
                        end
                 end
                case 1
                     if obj.counterCurrent + obj.counterP == 7 
                        obj.counterError = 0; % for 7 out 8 criterion
                        obj.counterP = 0;
                        obj.counterCurrent = 0;
                        notify(obj,'Reversal');  % notify data summary JZ10/10/11
                        %obj.countset(1) = obj.countset(1) + 1;
                        obj.ReversalN = obj.ReversalN+1; %count reversal
                        switch obj.currentStimNumber%% switch the rewarded window after reversal! JZ 10/11/2011
                            case 1
                            obj.default.correctresponse = {[5]};
                            obj.currentStimNumber = 2;
                            obj.currentStim = obj.stimSet{obj.currentStimNumber};
                            obj.touchDisplayObj.prepareNextStimulus(obj.currentStim);
                            case 2
                            obj.default.correctresponse = {[3]};
                            obj.currentStimNumber = 1;
                            obj.currentStim = obj.stimSet{obj.currentStimNumber};
                            obj.touchDisplayObj.prepareNextStimulus(obj.currentStim);
                        end
                     end
                     
            end
                    
%                 if round(obj.countset(1)/2) ~= obj.countset(1)/2% decide which rewarded first
%                     obj.default.correctresponse = {[6]};
%                     obj.currentStimNumber = 2;
%                     obj.currentStim = obj.stimSet{obj.currentStimNumber};
%                     obj.touchDisplayObj.prepareNextStimulus(obj.currentStim);
%                 elseif round(obj.countset(1)/2) == obj.countset(1)/2
%                     obj.default.correctresponse = {[2]};
%                     obj.currentStimNumber = 1;
%                     obj.currentStim = obj.stimSet{obj.currentStimNumber};
%                     obj.touchDisplayObj.prepareNextStimulus(obj.currentStim);
%                 end;
            
           
        end
        function endInterTrialFcn(obj,src,evnt)
            % Prepare the Next Stimulus
            nstim = size(obj.stimSet,1);
            switch obj.stimOrder
                case 'sequential'
                    if obj.currentStimNumber == nstim
                        obj.currentStimNumber = 1;
                    else
                        obj.currentStimNumber = obj.currentStimNumber+1;
                    end
                case 'random'
                    obj.currentStimNumber = ceil(nstim*rand);
            end
            obj.currentStim = obj.stimSet{obj.currentStimNumber};
            obj.touchDisplayObj.prepareNextStimulus(obj.currentStim); % e.g. currentStim = [3 5]
            % Transition to Wait4Poke Phase
            obj.houseLight('on') % works in reverse. so ON == OFF
            if ~obj.shouldContinue       
                obj.trialPhase = 'wait4poke';
                obj.rewardLight('on')
            else % the nose-poke was poked during the ITI
                obj.trialPhase = 'wait4poke';
                obj.rewardLight('on')
            end
            fprintf('%s',datestr(now,'HH:MM:SS'))
            notify(obj,'TrialStart')
        end
        
        function startPunishFcn(obj,src,evnt)
             obj.houseLight('off') %JZ 10/15/11
              obj.laser('off');%JZ 12/9%%%  It is crucial to turn off the laser after touch the wrong white square
             
        end
        function endPunishFcn(obj,src,evnt)
            % Prepare the Next Stimulus
%             nstim = size(obj.stimSet,1);
%             switch obj.stimOrder
%                 case 'sequential'
%                     if obj.currentStimNumber == nstim
%                         obj.currentStimNumber = 1;
%                     else
%                         obj.currentStimNumber = obj.currentStimNumber+1;
%                     end
%                 case 'random'
%                     obj.currentStimNumber = ceil(nstim*rand);
%             end
%             obj.currentStim = obj.stimSet{obj.currentStimNumber};
%             obj.touchDisplayObj.prepareNextStimulus(obj.currentStim); % e.g. currentStim = [3 5]
%             % Transition to Wait4Poke Phase
        obj.houseLight('on') % works in reverse. so ON == OFF %JZ 10/15/2011           
        if ~obj.shouldContinue
                obj.trialPhase = 'wait4poke';
                obj.rewardLight('on')
            else % the nose-poke was poked during the ITI
                obj.trialPhase = 'wait4poke';
                obj.rewardLight('on')
            end
           
            obj.trialPhaseNum = 0;     % to set the trail as failed JZ
            obj.counterError = obj.counterError+ 1;
                    switch obj.counterError
                        case 1
                            obj.counterP = obj.counterCurrent;
                            obj.counterCurrent = 0;
                        case 2    
                            obj.counterError = 1;
                            obj.counterP = obj.counterCurrent;
                            obj.counterCurrent = 0;
                        %obj.countset(2) = obj.countset(2) + 1;
                    end
                     
            obj.currentStim = obj.stimSet{obj.currentStimNumber};
            obj.touchDisplayObj.prepareNextStimulus(obj.currentStim); % e.g. currentStim = [3 5]
            % Transition to Wait4Poke Phase
                     
            fprintf('%s',datestr(now,'HH:MM:SS'))
            notify(obj,'TrialStart')
        end
        
        function startPauseFcn(obj,src,evnt)
            obj.trialPhase = 'pause';
        end
        function endPauseFcn(obj,src,evnt)
            obj.giveReward();
            fprintf('%s',datestr(now,'HH:MM:SS'))
            notify(obj,'Reward');
            obj.trialPhase = 'reward';
            obj.trialPhaseNum = 1;     
            obj.shouldContinue = false;
            start(obj.interTrialTimer)
        end
    end
    methods % Cleanup
        function delete(obj)
            clear global
            delete(obj.touchDisplayObj)
            delete(obj.nidaqObj)
            delete(obj.speakerObj)
            delete(obj.stimulusTimer)
           % delete(obj.laserTimer) % JZ 12/9
            delete(obj.interTrialTimer)           
            delete(obj.dataSummaryObj)
        end
    end
    
end



function deleteTimerFcn(src,evnt)
delete(src);
end














