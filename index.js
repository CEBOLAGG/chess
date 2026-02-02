// Dependancies
const express = require("express");
const bodyParser = require("body-parser");

// Engine path
const enginePath = "stockfish.exe";

// Setup server
const app = express();

// Parse data into body
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Setup chess engine
const Engine = require("node-uci").Engine;
var engine = new Engine(enginePath);

async function setup() {
  engine = new Engine(enginePath);
  await engine.init();

  // Configurações otimizadas para máxima força
  await engine.setoption("Hash", 4096);
  await engine.setoption("Threads", 8);
  await engine.setoption("MultiPV", 1);
  await engine.setoption("Ponder", false);
  await engine.setoption("Contempt", 0);
  await engine.setoption("Move Overhead", 30);
  await engine.setoption("Minimum Thinking Time", 1000);
  await engine.setoption("Slow Mover", 100);

  await engine.isready();
}

// Extrai a última informação válida do array
function getLastInfo(infoArray) {
  if (!Array.isArray(infoArray)) return null;

  // Procura do fim para o início pela última entrada com dados completos
  for (let i = infoArray.length - 1; i >= 0; i--) {
    const info = infoArray[i];
    if (info.depth && info.score) {
      return info;
    }
  }

  return null;
}

// Analisa o score e detecta mate
function analyzeMate(info) {
  if (!info || !info.score) return { isMate: false };

  // Formato: { unit: 'mate', value: 3 } ou { unit: 'cp', value: 100 }
  if (info.score.unit === "mate") {
    const mateValue = info.score.value;
    return {
      isMate: true,
      movesToMate: Math.abs(mateValue),
      mateForWhite: mateValue > 0,
    };
  }

  return { isMate: false };
}

// Formata mensagem de mate
function formatMateMessage(mateInfo, playerColor) {
  if (!mateInfo || !mateInfo.isMate) return null;

  const moves = mateInfo.movesToMate;
  const isPlayerMating =
    (playerColor === "w" && mateInfo.mateForWhite) ||
    (playerColor === "b" && !mateInfo.mateForWhite);

  if (isPlayerMating) {
    return `🎯 MATE EM ${moves} MOVIMENTO${moves > 1 ? "S" : ""}!`;
  } else {
    return `⚠️ MATE EM ${moves} MOVIMENTO${moves > 1 ? "S" : ""}!`;
  }
}

(async () => {
  await setup();

  // Routes
  app.get("/api/solve", async (req, res) => {
    try {
      await engine.position(req.query.fen);

      const fenParts = req.query.fen.split(" ");
      const playerColor = fenParts[1];
      const depth = parseInt(req.query.depth) || 25;

      const result = await engine.go({
        depth: depth,
      });

      const lastInfo = getLastInfo(result.info);
      const mateInfo = analyzeMate(lastInfo);
      const mateMessage = formatMateMessage(mateInfo, playerColor);

      const response = {
        move: result.bestmove,
        depth: lastInfo?.depth,
        score: lastInfo?.score,
        nodes: lastInfo?.nodes,
        mate: mateInfo,
        message: mateMessage,
      };

      if (req.query.detailed === "true") {
        res.json(response);
      } else {
        res.send(result.bestmove);
      }
    } catch (error) {
      await setup();
      res.status(500).send("Failed to get AI result!");
    }
  });

  // Rota detalhada - APENAS análise normal, sem busca específica de mate
  app.get("/api/analyze", async (req, res) => {
    try {
      await engine.position(req.query.fen);

      const fenParts = req.query.fen.split(" ");
      const playerColor = fenParts[1];
      const depth = parseInt(req.query.depth) || 25;

      // Apenas busca normal profunda - SEM busca específica de mate
      const result = await engine.go({
        depth: depth,
      });

      const lastInfo = getLastInfo(result.info);
      const mateInfo = analyzeMate(lastInfo);
      const mateMessage = formatMateMessage(mateInfo, playerColor);

      const response = {
        bestmove: result.bestmove,
        depth: lastInfo?.depth || null,
        score: lastInfo?.score || null,
        nodes: lastInfo?.nodes || null,
        nps: lastInfo?.nps || null,
        time: lastInfo?.time || null,
        mate: mateInfo,
        message: mateMessage,
        pv: lastInfo?.pv || null,
      };

      res.json(response);
    } catch (error) {
      await setup();
      res
        .status(500)
        .json({ error: "Failed to analyze position", details: error.message });
    }
  });

  // Rota de status
  app.get("/api/status", (req, res) => {
    res.json({
      status: "online",
      engine: "Stockfish",
      config: {
        hash: "4096 MB",
        threads: 8,
        depth: 20,
      },
    });
  });

  // Start listening
  app.listen(3000);

  // Graceful shutdown
  process.on("SIGINT", async () => {
    await engine.quit();
    process.exit(0);
  });
})();
