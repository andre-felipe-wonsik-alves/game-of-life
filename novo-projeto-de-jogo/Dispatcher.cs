using Godot;
using Godot.Collections;
using System.Threading.Tasks;

public partial class Dispatcher : Node
{
    [ExportGroup("Settings")]
    [Export(PropertyHint.Range, "1, 1000")] private int _updateFrequency = 60;
    [Export] private bool _autoStart;
    [Export] private Texture2D _dataTexture;

    
}