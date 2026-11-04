# Nekadaja

**A Modern Learning Management System**

Nekadaja is a Learning Management System (LMS) platform designed to provide a structured, accessible, and scalable digital learning experience.

The project is built with a modern technology stack, focusing on maintainability, performance, security, and scalability.

## Project Overview

Nekadaja aims to provide a centralized learning platform where users can access courses, study materials, assessments, and monitor their learning progress.

The platform is developed using a monorepo architecture, separating application code and infrastructure configurations.

## Technology Stack

| Component          | Technology     |
| ------------------ | -------------- |
| Backend            | Go (Golang)    |
| Backend Framework  | Gin            |
| Frontend           | Next.js        |
| Database           | PostgreSQL     |
| Database Driver    | pgx            |
| SQL Generator      | sqlc           |
| Cache              | Redis          |
| Database Migration | golang-migrate |
| Infrastructure     | Docker         |
| Version Control    | Git            |

## Project Structure

```text
nekadaja/
├── backend/
│   ├── cmd/
│   ├── internal/
│   ├── migrations/
│   ├── queries/
│   ├── tests/
│   ├── docs/
│   ├── go.mod
│   └── go.sum
│
├── frontend/
│
├── infrastructure/
│   ├── docker/
│   └── nginx/
│
├── docs/
│
├── .gitignore
└── README.md
```

## Architecture

Nekadaja uses a Modular Monolith architecture for its backend.

The application is organized into independent business modules to maintain clear separation of responsibilities while keeping deployment and infrastructure management simple.

Main backend modules include:

- Authentication & Authorization
- User Management
- Course Management
- Category Management
- Learning Materials
- Enrollment Management
- Examination & Assessment
- Payment Management

## Development Setup

### Prerequisites

Make sure the following tools are installed:

- Go
- Node.js and npm
- Docker
- Docker Compose
- Git

### Clone Repository

```bash
git clone https://github.com/AsepNurdinDev/nekadaja.git
cd nekadaja
```

### Backend Setup

```bash
cd backend

cp .env.example .env

go mod tidy

go run ./cmd/api
```

### Frontend Setup

Frontend development instructions will be added when the Next.js application is initialized.

## Development Roadmap

- [x] Initial project structure
- [x] Backend Go module initialization
- [x] Gin framework integration
- [ ] Backend configuration management
- [ ] PostgreSQL infrastructure
- [ ] Redis infrastructure
- [ ] Database migration setup
- [ ] SQLC configuration
- [ ] Authentication & authorization
- [ ] Core LMS modules
- [ ] Examination system
- [ ] Payment integration
- [ ] Frontend development
- [ ] Production deployment
- [ ] Monitoring and observability

## Development Principles

- Modular and maintainable architecture
- Secure authentication and authorization
- Database consistency and integrity
- Containerized infrastructure
- Clean separation of application responsibilities
- Automated testing and deployment

## Project Status

**Currently under active development.**

Nekadaja is in its initial development phase, focusing on backend foundation and infrastructure preparation.

## License

License has not been defined yet.
