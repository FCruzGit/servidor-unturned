// Module do Unturned que salva o mundo periodicamente (o jogo so salva no "save" manual e no shutdown).
// Intervalo e arquivo-marcador vem das variaveis de ambiente definidas pelo executor:
//   UT_AUTOSAVE_MINUTOS  (padrao 5)
//   UT_AUTOSAVE_MARCADOR (arquivo atualizado apos cada save; o executor usa para disparar backups)
using System;
using System.Globalization;
using System.IO;
using SDG.Framework.Modules;
using SDG.Unturned;
using UnityEngine;

namespace UtAutosave
{
    public class Nexus : IModuleNexus
    {
        private GameObject host;

        public void initialize()
        {
            host = new GameObject("UtAutosave");
            UnityEngine.Object.DontDestroyOnLoad(host);
            host.AddComponent<Autosaver>();
            host.AddComponent<Painel>();
            host.AddComponent<SpawnFixo>();
        }

        public void shutdown()
        {
            if (host != null) UnityEngine.Object.Destroy(host);
        }
    }

    public class Autosaver : MonoBehaviour
    {
        private float intervalo;
        private float proximo = -1f;
        private string marcador;

        private void Awake()
        {
            float minutos;
            if (!float.TryParse(Environment.GetEnvironmentVariable("UT_AUTOSAVE_MINUTOS"), NumberStyles.Float, CultureInfo.InvariantCulture, out minutos) || minutos <= 0f)
                minutos = 5f;
            intervalo = minutos * 60f;
            marcador = Environment.GetEnvironmentVariable("UT_AUTOSAVE_MARCADOR");
            CommandWindow.Log("[Autosave] Ativo: salvando o mundo a cada " + minutos.ToString(CultureInfo.InvariantCulture) + " minuto(s).");
        }

        private void Update()
        {
            if (!Provider.isServer || !Level.isLoaded)
            {
                proximo = -1f;
                return;
            }
            float agora = Time.realtimeSinceStartup;
            if (proximo < 0f)
            {
                proximo = agora + intervalo;
                return;
            }
            if (agora < proximo) return;
            proximo = agora + intervalo;

            try
            {
                SaveManager.save();
                CommandWindow.Log("[Autosave] Mundo salvo as " + DateTime.Now.ToString("HH:mm:ss") + ".");
                if (!string.IsNullOrEmpty(marcador)) File.WriteAllText(marcador, DateTime.Now.ToString("o"));
            }
            catch (Exception e)
            {
                CommandWindow.LogError("[Autosave] Falha ao salvar: " + e);
            }
        }
    }
}
