// Ponte entre o servidor e o painel web (scripts\Painel.ps1). Ativa quando o executor define UT_PAINEL_DIR:
//   - executa os comandos que o painel deixa em <UT_PAINEL_DIR>\cmd\*.cmd (um comando por arquivo, em ordem de nome);
//   - escreve <UT_PAINEL_DIR>\status.json a cada 2 s (mapa carregado, jogadores online);
//   - com UT_OCULTAR_CONSOLE=1, esconde a janela de console do servidor (modo silencioso).
using System;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using SDG.Unturned;
using Steamworks;
using UnityEngine;

namespace UtAutosave
{
    public class Painel : MonoBehaviour
    {
        [DllImport("kernel32.dll")] private static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);

        private string dir;
        private string cmdDir;
        private bool ocultar;
        private float proximoCmd;
        private float proximoStatus;
        private float proximoConsole;
        private string ultimoStatus;
        private float ultimoStatusEm;
        public static bool ListaPronta;
        private bool listaEscrita;

        private void Awake()
        {
            dir = Environment.GetEnvironmentVariable("UT_PAINEL_DIR");
            ocultar = Environment.GetEnvironmentVariable("UT_OCULTAR_CONSOLE") == "1";
            if (string.IsNullOrEmpty(dir)) { enabled = ocultar; return; }
            cmdDir = Path.Combine(dir, "cmd");
            Directory.CreateDirectory(cmdDir);
            CommandWindow.Log("[Painel] Conectado ao painel web.");
        }

        private void Update()
        {
            float agora = Time.realtimeSinceStartup;
            if (ocultar && agora >= proximoConsole)
            {
                proximoConsole = agora + 1f;
                try
                {
                    IntPtr h = GetConsoleWindow();
                    if (h != IntPtr.Zero && IsWindowVisible(h)) ShowWindow(h, 0);
                }
                catch (Exception) { ocultar = false; }
            }
            if (string.IsNullOrEmpty(dir)) return;
            if (agora >= proximoCmd)
            {
                proximoCmd = agora + 0.5f;
                ExecutarComandos();
            }
            if (ListaPronta && !listaEscrita) { listaEscrita = true; EscreverComandos(); }
            if (agora >= proximoStatus)
            {
                proximoStatus = agora + 2f;
                EscreverStatus(agora);
            }
        }

        private void ExecutarComandos()
        {
            string[] arquivos;
            try { arquivos = Directory.GetFiles(cmdDir, "*.cmd"); } catch (Exception) { return; }
            Array.Sort(arquivos, StringComparer.Ordinal);
            foreach (string arq in arquivos)
            {
                string texto;
                try
                {
                    texto = File.ReadAllText(arq, Encoding.UTF8).Trim();
                    File.Delete(arq);
                }
                catch (Exception) { continue; }
                if (texto.Length == 0) continue;
                CommandWindow.Log("[Painel] > " + texto);
                try
                {
                    if (!Commander.execute(CSteamID.Nil, texto))
                        CommandWindow.LogWarning("[Painel] Comando desconhecido: " + texto);
                }
                catch (Exception e)
                {
                    CommandWindow.LogError("[Painel] Falha no comando: " + e.Message);
                }
            }
        }

        private void EscreverStatus(float agora)
        {
            try
            {
                StringBuilder sb = new StringBuilder();
                sb.Append("{\"carregado\":").Append(Provider.isServer && Level.isLoaded ? "true" : "false");
                sb.Append(",\"mapa\":").Append(Json(Level.info != null ? Level.info.name : ""));
                sb.Append(",\"spawn\":").Append(SpawnFixo.Definido ? Json(SpawnFixo.Texto()) : "null");
                sb.Append(",\"max\":").Append(Provider.maxPlayers.ToString(CultureInfo.InvariantCulture));
                sb.Append(",\"jogadores\":[");
                bool primeiro = true;
                foreach (SteamPlayer p in Provider.clients)
                {
                    if (!primeiro) sb.Append(',');
                    primeiro = false;
                    sb.Append("{\"personagem\":").Append(Json(p.playerID.characterName));
                    sb.Append(",\"steam\":").Append(Json(p.playerID.playerName));
                    sb.Append(",\"id\":").Append(Json(p.playerID.steamID.m_SteamID.ToString(CultureInfo.InvariantCulture)));
                    sb.Append(",\"ping\":").Append(((int)(p.ping * 1000f)).ToString(CultureInfo.InvariantCulture));
                    sb.Append(",\"admin\":").Append(p.isAdmin ? "true" : "false");
                    sb.Append('}');
                }
                sb.Append("]}");
                // So grava se mudou; a cada 5 s grava mesmo assim (o painel considera parado um status com mais de 10 s)
                string json = sb.ToString();
                if (json == ultimoStatus && agora - ultimoStatusEm < 5f) return;
                ultimoStatus = json;
                ultimoStatusEm = agora;
                string tmp = Path.Combine(dir, "status.tmp");
                File.WriteAllText(tmp, json, new UTF8Encoding(false));
                string final = Path.Combine(dir, "status.json");
                if (File.Exists(final)) File.Delete(final);
                File.Move(tmp, final);
            }
            catch (Exception) { }
        }

        // Lista de comandos do servidor (para as sugestoes do console do painel)
        private void EscreverComandos()
        {
            try
            {
                StringBuilder sb = new StringBuilder("[");
                bool primeiro = true;
                foreach (Command c in Commander.commands)
                {
                    if (c == null || string.IsNullOrEmpty(c.command)) continue;
                    if (!primeiro) sb.Append(',');
                    primeiro = false;
                    sb.Append("{\"c\":").Append(Json(c.command)).Append(",\"info\":").Append(Json(c.info)).Append(",\"help\":").Append(Json(c.help)).Append('}');
                }
                sb.Append(']');
                File.WriteAllText(Path.Combine(dir, "comandos.json"), sb.ToString(), new UTF8Encoding(false));
            }
            catch (Exception e) { CommandWindow.LogWarning("[Painel] Falha ao listar comandos: " + e.Message); }
        }

        private static string Json(string s)
        {
            if (s == null) return "\"\"";
            StringBuilder sb = new StringBuilder("\"");
            foreach (char c in s)
            {
                if (c == '"' || c == '\\') sb.Append('\\').Append(c);
                else if (c < ' ') sb.Append("\\u").Append(((int)c).ToString("x4"));
                else sb.Append(c);
            }
            return sb.Append('"').ToString();
        }
    }
}
