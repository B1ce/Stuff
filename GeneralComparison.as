// GeneralComparison.as

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

// Global Storage
array<GhostSample>@ referenceRun = array<GhostSample>();

bool isRecording = false;
bool hasReference = false;

// Settings
int recordingInterval = 1; 

// State Variables
int lastClosestIndex = 0;
int lastRecordedTime = -1;
int tickCounter = 0; 
int lastDisplayIndex = -1; // NEW: Tracks when to update the UI

// UI Variables
float ui_Delta = 0.0f;     
float ui_TimeDif = 0.0f;   
float ui_RefSpeed = 0.0f;
int ui_RefTime = 0;     

// Window State Flags
bool ui_OverlayInitialized = false; 
bool ui_ControlsInitialized = false;
bool ui_LockOverlay = false;        

PluginInfo@ GetPluginInfo()
{
    PluginInfo info;
    info.Name = "General Comparison";
    info.Author = "Bice with Gemini3";
    info.Version = "1.0";
    info.Description = "Compares the time and speed difference based on position";
    return info;
}

float GetExactSpeed(vec3 velocity)
{
    return Math::Distance(vec3(0,0,0), velocity) * 3.6f;
}

void ClearReferenceMemory()
{
    @referenceRun = null;
    @referenceRun = array<GhostSample>();
    lastDisplayIndex = -1; // Reset display tracker
}

// --- LOGIC LOOP ---
void OnRunStep(SimulationManager@ sim)
{
    if (sim is null || sim.PlayerInfo is null || sim.Dyna is null) return;
    
    if (referenceRun is null) @referenceRun = array<GhostSample>();

    int currentRaceTime = sim.PlayerInfo.RaceTime;

    // Auto-Stop Recording
    if (isRecording && sim.PlayerInfo.RaceFinished)
    {
        isRecording = false;
        hasReference = true;
        lastClosestIndex = 0;
        return; 
    }

    // Reset detection
    if (isRecording)
    {
        if (lastRecordedTime != -1 && currentRaceTime < lastRecordedTime)
        {
            ClearReferenceMemory();
            lastRecordedTime = -1; 
            tickCounter = 0; 
        }
    }
    else
    {
        if (currentRaceTime < 100) 
        {
            lastClosestIndex = 0;
            lastDisplayIndex = -1; // Reset on restart
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
                if (tickCounter % recordingInterval == 0)
                {
                    vec3 velocity = sim.Dyna.CurrentState.LinearSpeed;
                    float preciseSpeed = GetExactSpeed(velocity);
                    referenceRun.Add(GhostSample(currentPos, preciseSpeed, currentRaceTime));
                }
                lastRecordedTime = currentRaceTime;
            }
        }
        else if (hasReference && referenceRun.Length > 0)
        {
            int searchRadius = 150; 
            int len = int(referenceRun.Length);
            int startIndex = Math::Max(0, lastClosestIndex - searchRadius);
            int endIndex = Math::Min(len - 1, lastClosestIndex + searchRadius);
            
            float closestDist = 999999.0f;
            int bestIndex = lastClosestIndex;

            for (int i = startIndex; i <= endIndex; i++)
            {
                float dist = Math::Distance(currentPos, referenceRun[i].Position);
                if (dist < closestDist)
                {
                    closestDist = dist;
                    bestIndex = i;
                }
            }
            
            lastClosestIndex = bestIndex;
            
            // --- NEW: STABILITY CHECK ---
            // Only recalculate the output if we have actually matched a NEW sample.
            // If we are still closest to the same sample as last tick, we hold the old values.
            if (bestIndex != lastDisplayIndex)
            {
                lastDisplayIndex = bestIndex; // Update the tracker

                vec3 velocity = sim.Dyna.CurrentState.LinearSpeed;
                float preciseSpeed = GetExactSpeed(velocity);
                
                ui_RefSpeed = referenceRun[bestIndex].Speed;
                ui_Delta = preciseSpeed - ui_RefSpeed;

                ui_RefTime = referenceRun[bestIndex].Time; 
                ui_TimeDif = float(ui_RefTime - currentRaceTime) / 1000.0f;
            }
        }
    }
}

// --- RENDER LOOP ---
void Render()
{
    if (referenceRun is null) @referenceRun = array<GhostSample>();

    // --- 1. Control Panel ---
    if (!ui_ControlsInitialized)
    {
        UI::SetNextWindowPos(vec2(100, 100));
	UI::SetNextWindowSize(vec2(550, 160));
        ui_ControlsInitialized = true;
    }

    int controlFlags = 0; 
    
    if (UI::Begin("Comparison Controls", controlFlags))
    {
        if (!hasReference)
        {
            UI::Text("Drive the comparison run and record it");
            
            recordingInterval = UI::SliderInt("##RecInterval", recordingInterval, 1, 10);
            UI::Text("Recording interval: Smaller number = more accurate, but more memory usage");
            
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
                UI::TextDimmed("(Auto-stops when finishing)");
                UI::Text("Samples: " + referenceRun.Length);
            }
        }
        else
        {
            UI::Text("Ref: " + referenceRun.Length + " samples");
            
            if (UI::Button("Clear Reference"))
            {
                hasReference = false;
                ClearReferenceMemory();
            }
        }
    }
    UI::End();

    // --- 2. Data Overlay ---
    auto sim = GetSimulationManager();
    if (sim !is null && sim.PlayerInfo !is null && sim.PlayerInfo.RaceTime > 0 && hasReference && !isRecording)
    {
        if (!ui_OverlayInitialized)
        {
            UI::SetNextWindowPos(vec2(600, 300));
            UI::SetNextWindowSize(vec2(200, 100));
            ui_OverlayInitialized = true;
        }

        int overlayFlags = 0;
        if (ui_LockOverlay)
        {
            overlayFlags |= UI::WindowFlags::NoTitleBar | UI::WindowFlags::NoBackground | UI::WindowFlags::NoMove | UI::WindowFlags::NoMouseInputs | UI::WindowFlags::NoResize;
        }
        else
        {
            overlayFlags |= UI::WindowFlags::NoTitleBar; 
        }

        if (UI::Begin("Speed Delta", overlayFlags))
        {
            // Speed Diff
            string signSpeed = (ui_Delta > 0) ? "+" : "";
            vec4 colorSpeed;
            if (ui_Delta > 0) colorSpeed = vec4(0, 1, 0, 1);       
            else if (ui_Delta < 0) colorSpeed = vec4(1, 0, 0, 1);  
            else colorSpeed = vec4(1, 1, 1, 1);                    

            UI::PushStyleColor(UI::Col::Text, colorSpeed);
            UI::Text("SpeedDif: " + signSpeed + Text::FormatFloat(ui_Delta, "", 0, 3));
            UI::PopStyleColor();

            // Time Diff
            string displaySign = (ui_TimeDif > 0) ? "-" : ""; 
            vec4 colorTime;
            if (ui_TimeDif > 0) colorTime = vec4(0, 1, 0, 1);      
            else if (ui_TimeDif < 0) colorTime = vec4(1, 0, 0, 1); 
            else colorTime = vec4(1, 1, 1, 1);

            UI::PushStyleColor(UI::Col::Text, colorTime);
            UI::Text("TimeDif:  " + displaySign + Text::FormatFloat(ui_TimeDif, "", 0, 3));
            UI::PopStyleColor();
            
            UI::Separator();
            
            UI::TextDimmed("Ref Speed: " + Text::FormatFloat(ui_RefSpeed, "", 0, 3));
            UI::TextDimmed("Ref Time:  " + Time::Format(ui_RefTime));
        }
        UI::End();
    }
}