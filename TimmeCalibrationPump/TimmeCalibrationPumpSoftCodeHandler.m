% This function handles the softcodes in the protocol.

function TimmeCalibrationPumpSoftCodeHandler(SoftCodeID)
% SoftCodeID is an integer that identifies the action that should be taken.


global pump



if SoftCodeID == 1
    % Trigger the pump
    fwrite(pump, char([114 117 110 13 10]));
    
else
    error('Unknown soft code.')
end
