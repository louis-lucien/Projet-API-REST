-- Création des tables avec des contraintes d'unicité
CREATE TABLE groups (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);

CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    role VARCHAR(50) CHECK (role IN ('admin', 'user')) NOT NULL,
    group_id INT REFERENCES groups(id)
);

CREATE TABLE prompts (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    price NUMERIC DEFAULT 1000,
    rating INT CHECK (rating BETWEEN -10 AND 10) DEFAULT 0,
    status VARCHAR(50) CHECK (status IN ('En attente', 'Activer', 'À revoir', 'Rappel', 'À supprimer')) DEFAULT 'En attente',
    user_id INT REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE votes (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    prompt_id INT REFERENCES prompts(id),
    vote INT CHECK (vote IN (1, 2)), -- 2 pour les membres du groupe, 1 pour les autres
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    CONSTRAINT unique_vote UNIQUE (user_id, prompt_id)
);

-- Création des index
CREATE INDEX idx_users_username ON users (username);
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_prompts_status ON prompts (status);

-- Fonction pour recalculer le prix d'un prompt après chaque notation
CREATE OR REPLACE FUNCTION recalculate_price() RETURNS TRIGGER AS $$
BEGIN
    NEW.price := 1000 * (1 + NEW.rating);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Déclencheur pour recalculer le prix d'un prompt
CREATE TRIGGER trg_recalculate_price
AFTER UPDATE OF rating ON prompts
FOR EACH ROW
EXECUTE FUNCTION recalculate_price();

-- Déclencheur pour mettre à jour le statut du prompt après chaque insertion de vote
CREATE TRIGGER trg_update_prompt_status
AFTER INSERT ON votes
FOR EACH ROW
EXECUTE FUNCTION update_prompt_status();
-- Fonction pour mettre à jour le statut du prompt après chaque insertion de vote
CREATE OR REPLACE FUNCTION update_prompt_status() RETURNS TRIGGER AS $$
DECLARE
    total_points DECIMAL;
BEGIN
    -- Calculer le score total des votes pour le prompt
    SELECT SUM(CASE WHEN u.group_id IS NOT NULL THEN v.vote * 0.6 ELSE v.vote * 0.4 END)
    INTO total_points
    FROM votes v
    INNER JOIN users u ON v.user_id = u.id
    WHERE v.prompt_id = NEW.prompt_id;

    -- Mettre à jour la note moyenne du prompt
    UPDATE prompts
    SET rating = total_points / (SELECT COUNT(*) FROM votes WHERE prompt_id = NEW.prompt_id)
    WHERE id = NEW.prompt_id;

    -- Mettre à jour le statut du prompt s'il atteint 6 points
    IF total_points >= 6 THEN
        UPDATE prompts SET status = 'Activer' WHERE id = NEW.prompt_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Déclencheur pour gérer l'insertion de votes
CREATE TRIGGER trg_insert_vote
BEFORE INSERT ON votes
FOR EACH ROW
EXECUTE FUNCTION insert_vote();

-- Créer les rôles et permissions
CREATE ROLE admin;
CREATE ROLE user;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE users TO admin;
GRANT SELECT, INSERT, UPDATE ON TABLE users TO user;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE prompts TO admin;
GRANT SELECT, INSERT, UPDATE ON TABLE prompts TO user;
