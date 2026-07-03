class GhostSample
{
    vec3 Position;
    float Speed;
    int Time;
    
    GhostSample() { } 
    
    GhostSample(vec3 pos, float speed, int time)
    {
        this.Position = pos;
        this.Speed = speed;
        this.Time = time;
    }
}

array<GhostSample>@ referenceRun = array<GhostSample>();

bool isRecording = false;
bool hasReference = false;

bool useRecordingInterval = false; 
int recordingInterval = 1; 
bool showRefStats = false; 

int lastClosestIndex = 0;
int lastRecordedTime = -1;
int tickCounter = 0; 
int lastDisplayIndex = -1;

float ui_Delta = 0.0f;     
float ui_TimeDif = 0.0f;   
float ui_RefSpeed = 0.0f;
int ui_RefTime = 0;     

bool ui_ControlsInitialized = false;

PluginInfo@ GetPluginInfo()
{
    PluginInfo info;
    info.Name = "General Comparison";
    info.Author = "Bice with Gemini3";
    info.Version = "2.2";
    info.Description = "Compares the time and speed difference based on position";
    return info;
}

float DistSq(vec3 a, vec3 b)
{
    return (a.x - b.x)*(a.x - b.x) + (a.y - b.y)*(a.y - b.y) + (a.z - b.z)*(a.z - b.z);
}

float GetExactSpeed(vec3 velocity)
{
    return Math::Sqrt(velocity.x*velocity.x + velocity.y*velocity.y + velocity.z*velocity.z) * 3.6f;
}

void ClearReferenceMemory()
{
    referenceRun.Resize(0);
    lastDisplayIndex = -1;
    lastClosestIndex = 0; 
}

void TruncateRecording(int timeLimit)
{
    if (referenceRun.Length == 0) return;

    uint newLength = referenceRun.Length;
    for (int i = int(referenceRun.Length) - 1; i >= 0; i--)
    {
        if (referenceRun[i].Time <= timeLimit)
        {
            newLength = i + 1;
            break;
        }
        if (i == 0) newLength = 0;
    }

    if (newLength < referenceRun.Length)
    {
        referenceRun.Resize(newLength);
    }
}

void OnRunStep(SimulationManager@ sim)
{
    if (sim is null || sim.PlayerInfo is null || sim.Dyna is null || sim.Dyna.CurrentState is null) return;

    int currentRaceTime = sim.PlayerInfo.RaceTime;

    if (isRecording && sim.PlayerInfo.RaceFinished)
    {
        isRecording = false;
        hasReference = true;
        lastClosestIndex = 0;
        return; 
    }

    if (isRecording)
    {
        if (lastRecordedTime != -1 && currentRaceTime < lastRecordedTime)
        {
            TruncateRecording(currentRaceTime);
            lastRecordedTime = currentRaceTime;
            tickCounter = 0; 
        }
    }
    else
    {
        if (currentRaceTime < 100) 
        {
            lastClosestIndex = 0;
            lastDisplayIndex = -1; 
        }
    }

    if (currentRaceTime > 0)
    {
        vec3 currentPos = sim.Dyna.CurrentState.Location.Position;

        if (isRecording)
        {
            if (currentRaceTime != lastRecordedTime)
            {
                tickCounter++;
                int activeInterval = useRecordingInterval ? recordingInterval : 1;
                
                if (tickCounter % activeInterval == 0)
                {
                    vec3 velocity = sim.Dyna.CurrentState.LinearSpeed;
                    referenceRun.Add(GhostSample(currentPos, GetExactSpeed(velocity), currentRaceTime));
                }
                lastRecordedTime = currentRaceTime;
            }
        }
        else if (hasReference && referenceRun.Length > 0)
        {
            int left = 0;
            int right = int(referenceRun.Length) - 1;
            int timeGuessIndex = lastClosestIndex;
            
            while (left <= right)
            {
                int mid = left + (right - left) / 2;
                
                if (referenceRun[mid].Time == currentRaceTime)
                {
                    timeGuessIndex = mid;
                    break;
                }
                else if (referenceRun[mid].Time < currentRaceTime)
                {
                    timeGuessIndex = mid;
                    left = mid + 1;
                }
                else
                {
                    right = mid - 1;
                }
            }
            
            int searchRadius = 150; 
            int startIndex = Math::Max(0, timeGuessIndex - searchRadius);
            int endIndex = Math::Min(int(referenceRun.Length) - 1, timeGuessIndex + searchRadius);
            
            float closestDistSq = 999999999.0f;
            int bestIndex = timeGuessIndex;

            for (int i = startIndex; i <= endIndex; i++)
            {
                float dSq = DistSq(currentPos, referenceRun[i].Position);
                if (dSq < closestDistSq)
                {
                    closestDistSq = dSq;
                    bestIndex = i;
                }
            }
            
            lastClosestIndex = bestIndex;
            
            if (bestIndex >= 0 && bestIndex < int(referenceRun.Length) && bestIndex != lastDisplayIndex)
            {
                lastDisplayIndex = bestIndex;

                ui_RefSpeed = referenceRun[bestIndex].Speed;
                ui_Delta = GetExactSpeed(sim.Dyna.CurrentState.LinearSpeed) - ui_RefSpeed;

                ui_RefTime = referenceRun[bestIndex].Time; 
                ui_TimeDif = float(ui_RefTime - currentRaceTime) / 1000.0f;
            }
        }
    }
}

void Render()
{
    if (!ui_ControlsInitialized)
    {
        UI::SetNextWindowPos(vec2(100, 100));
        ui_ControlsInitialized = true;
    }
    
    if (UI::Begin("General Comparison", UI::WindowFlags::AlwaysAutoResize))
    {
        auto sim = GetSimulationManager();
        bool isActivelyComparing = (sim !is null && sim.PlayerInfo !is null && sim.PlayerInfo.RaceTime > 0 && hasReference && !isRecording);
        
        if (!hasReference)
        {
            UI::Text("Record the Comparison Run");
            
            if (!isRecording)
            {
                if (UI::Button("Record"))
                {
                    ClearReferenceMemory();
                    isRecording = true;
                    lastRecordedTime = -1;
                    tickCounter = 0;
                }
            }
            else
            {
                if (UI::Button("Stop & Save"))
                {
                    isRecording = false;
                    hasReference = true;
                    lastClosestIndex = 0;
                }
                UI::SameLine();
                
                int currentFrame = (tickCounter / 10) % 4;
                string spinner = currentFrame == 0 ? "|" : currentFrame == 1 ? "/" : currentFrame == 2 ? "-" : "\\";
                
                UI::TextDimmed(spinner + " Recording");
                UI::Text("Samples Recorded: " + referenceRun.Length);
            }
        }
        else
        {
            if (UI::Button("Reset"))
            {
                hasReference = false;
                ClearReferenceMemory();
            }
        }

        if (hasReference && isActivelyComparing)
        {
            string signSpeed = "";
            vec4 colorSpeed = vec4(1, 1, 1, 1);
            if (ui_Delta > 0) { signSpeed = "+"; colorSpeed = vec4(0, 1, 0, 1); }
            else if (ui_Delta < 0) { colorSpeed = vec4(1, 0, 0, 1); }

            UI::PushStyleColor(UI::Col::Text, colorSpeed);
            UI::Text("SpeedDif: " + signSpeed + Text::FormatFloat(ui_Delta, "", 0, 3));
            UI::PopStyleColor();

            string displaySign = "";
            vec4 colorTime = vec4(1, 1, 1, 1);
            if (ui_TimeDif > 0) { displaySign = "+"; colorTime = vec4(0, 1, 0, 1); }
            else if (ui_TimeDif < 0) { colorTime = vec4(1, 0, 0, 1); }

            UI::PushStyleColor(UI::Col::Text, colorTime);
            UI::Text("TimeDif:  " + displaySign + Text::FormatFloat(ui_TimeDif, "", 0, 3));
            UI::PopStyleColor();
            
            if (showRefStats)
            {
                UI::TextDimmed("Ref Speed: " + Text::FormatFloat(ui_RefSpeed, "", 0, 3));
                UI::TextDimmed("Ref Time:  " + Time::Format(ui_RefTime));
            }
        }

        UI::Separator();
        
        if (UI::CollapsingHeader("Advanced Settings"))
        {
            useRecordingInterval = UI::Checkbox("Enable Custom Recording Interval", useRecordingInterval);
            if (useRecordingInterval)
            {
                UI::TextDimmed("Smaller Number = More Accurate, But More Memory");
                recordingInterval = UI::SliderInt("##RecInterval", recordingInterval, 1, 10);
            }
            
            UI::Dummy(vec2(0, 5));
            showRefStats = UI::Checkbox("Show Speed & Time Reference", showRefStats);
        }
    }
    UI::End();
}