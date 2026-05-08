# Code Documentation Reference

Covers inline docstrings, JSDoc, OpenAPI/Swagger specs, documentation sites, and developer guides.

---

## Python Docstrings

### Google Style (preferred for most projects)

```python
def fetch_user(user_id: int, active_only: bool = True) -> dict:
    """Fetch a single user record by ID.

    Args:
        user_id: Unique identifier for the user.
        active_only: When True, raise an error for inactive users.

    Returns:
        A dict containing user fields (id, name, email, created_at).

    Raises:
        ValueError: If user_id is not a positive integer.
        UserNotFoundError: If no matching user exists.

    Example:
        >>> fetch_user(42)
        {'id': 42, 'name': 'Alice', 'email': 'alice@example.com', ...}
    """
```

### NumPy Style (scientific/data projects)

```python
def compute_similarity(vec_a: np.ndarray, vec_b: np.ndarray) -> float:
    """Compute cosine similarity between two vectors.

    Parameters
    ----------
    vec_a : np.ndarray
        First input vector, shape (n,).
    vec_b : np.ndarray
        Second input vector, shape (n,).

    Returns
    -------
    float
        Cosine similarity in the range [-1, 1].

    Raises
    ------
    ValueError
        If vectors have different lengths.
    """
```

### Sphinx Style (legacy or Sphinx-based sites)

```python
def process_payment(order_id: str, amount: float) -> bool:
    """Process a payment for an order.

    :param order_id: The order identifier.
    :type order_id: str
    :param amount: Payment amount in USD.
    :type amount: float
    :returns: True if payment succeeded.
    :rtype: bool
    :raises PaymentError: If the payment gateway rejects the charge.
    """
```

### Validation

```bash
python -m doctest module.py            # run doctest examples
pytest --doctest-modules               # pytest integration
interrogate --fail-under=80 src/       # coverage check
```

---

## TypeScript / JavaScript JSDoc

### Function

```typescript
/**
 * Fetches a paginated list of products from the catalog.
 *
 * @param {string} categoryId - The category to filter by.
 * @param {number} [page=1] - Page number (1-indexed).
 * @param {number} [limit=20] - Maximum items per page.
 * @returns {Promise<ProductPage>} Resolves to a page of product records.
 * @throws {NotFoundError} If the category does not exist.
 *
 * @example
 * const page = await fetchProducts('electronics', 2, 10);
 * console.log(page.items[0].name);
 */
async function fetchProducts(
  categoryId: string,
  page = 1,
  limit = 20
): Promise<ProductPage> { ... }
```

### Class and Interface

```typescript
/**
 * Client for the orders API.
 *
 * @example
 * const client = new OrdersClient({ baseUrl: 'https://api.example.com' });
 * const order = await client.create({ productId: 'prod-1', quantity: 2 });
 */
class OrdersClient {
  /**
   * @param {OrdersClientOptions} options - Client configuration.
   */
  constructor(private options: OrdersClientOptions) {}

  /**
   * Create a new order.
   *
   * @param {CreateOrderInput} input - Order creation payload.
   * @returns {Promise<Order>} The created order.
   */
  async create(input: CreateOrderInput): Promise<Order> { ... }
}
```

### Validation

```bash
tsc --noEmit                           # type-check all JSDoc
npx typedoc --out docs src/            # generate HTML docs
```

---

## OpenAPI 3.1 Specification

### Complete Example

```yaml
openapi: "3.1.0"
info:
  title: Orders API
  version: "1.0.0"
  description: Manages customer orders and payment processing.

paths:
  /orders:
    post:
      summary: Create an order
      operationId: createOrder
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/CreateOrderInput"
            example:
              productId: "prod-123"
              quantity: 2
      responses:
        "201":
          description: Order created
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Order"
        "400":
          $ref: "#/components/responses/ValidationError"
        "401":
          $ref: "#/components/responses/Unauthorized"

  /orders/{orderId}:
    get:
      summary: Get an order by ID
      operationId: getOrder
      parameters:
        - name: orderId
          in: path
          required: true
          schema:
            type: string
            format: uuid
      responses:
        "200":
          description: Order found
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/Order"
        "404":
          $ref: "#/components/responses/NotFound"

components:
  schemas:
    CreateOrderInput:
      type: object
      required: [productId, quantity]
      properties:
        productId:
          type: string
          minLength: 1
        quantity:
          type: integer
          minimum: 1
          maximum: 100

    Order:
      type: object
      required: [id, productId, quantity, status, createdAt]
      properties:
        id:
          type: string
          format: uuid
        productId:
          type: string
        quantity:
          type: integer
        status:
          type: string
          enum: [pending, paid, shipped, cancelled]
        createdAt:
          type: string
          format: date-time

  responses:
    ValidationError:
      description: Request body failed validation
      content:
        application/json:
          schema:
            type: object
            properties:
              error:
                type: string
              details:
                type: array
                items:
                  type: string
    Unauthorized:
      description: Missing or invalid authentication token
    NotFound:
      description: Resource not found

  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT

security:
  - bearerAuth: []
```

### Validation

```bash
npx @redocly/cli lint openapi.yaml
npx @redocly/cli build-docs openapi.yaml --output docs/api.html
```

---

## FastAPI Auto-Documentation

```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from typing import Annotated

app = FastAPI(
    title="Orders API",
    version="1.0.0",
    description="Manages customer orders and payment processing.",
)

class CreateOrderInput(BaseModel):
    product_id: Annotated[str, Field(min_length=1, description="Product identifier")]
    quantity: Annotated[int, Field(ge=1, le=100, description="Units to order")]

class Order(BaseModel):
    id: str
    product_id: str
    quantity: int
    status: str

@app.post(
    "/orders",
    response_model=Order,
    status_code=201,
    summary="Create an order",
    responses={400: {"description": "Validation error"}},
)
async def create_order(body: CreateOrderInput) -> Order:
    """Create a new order.

    Returns the created order with an assigned ID and initial `pending` status.
    """
    return await order_service.create(body)
```

Access auto-generated docs at `/docs` (Swagger UI) and `/redoc`.

---

## NestJS Auto-Documentation (Swagger)

```typescript
import { ApiProperty, ApiOperation, ApiResponse } from "@nestjs/swagger";
import { IsString, IsInt, Min, Max } from "class-validator";

export class CreateOrderDto {
  @ApiProperty({ description: "Product identifier", minLength: 1 })
  @IsString()
  productId: string;

  @ApiProperty({ description: "Units to order", minimum: 1, maximum: 100 })
  @IsInt()
  @Min(1)
  @Max(100)
  quantity: number;
}

@Controller("orders")
export class OrdersController {
  @Post()
  @ApiOperation({ summary: "Create an order" })
  @ApiResponse({ status: 201, description: "Order created", type: OrderDto })
  @ApiResponse({ status: 400, description: "Validation error" })
  async create(@Body() dto: CreateOrderDto): Promise<OrderDto> { ... }
}
```

---

## Documentation Coverage

### Python — interrogate

```bash
pip install interrogate
interrogate --fail-under=80 --ignore-init-method src/
```

### TypeScript — typedoc-coverage

```bash
npx typedoc-coverage --fail-under=80 src/
```

### Coverage Targets

| Project Type | Minimum Coverage |
|-------------|-----------------|
| Public library | 95% |
| Internal service | 80% |
| CLI tool | 70% |
| Scripts/utilities | 50% |

---

## Documentation Sites

### MkDocs (Python projects)

```yaml
# mkdocs.yml
site_name: Orders API
theme:
  name: material
plugins:
  - search
  - mkdocstrings:
      handlers:
        python:
          options:
            docstring_style: google
nav:
  - Home: index.md
  - API Reference: reference/
  - Getting Started: getting-started.md
```

```bash
pip install mkdocs-material mkdocstrings[python]
mkdocs serve     # preview at http://localhost:8000
mkdocs build     # output to site/
```

### Getting Started Guide Structure

```markdown
# Getting Started

## Prerequisites
- Node.js 20+
- API key (obtain at dashboard.example.com)

## Installation
npm install @example/orders-sdk

## Quick Start
const client = new OrdersClient({ apiKey: process.env.API_KEY });
const order = await client.orders.create({ productId: "prod-1", quantity: 1 });

## Next Steps
- [Authentication](./auth.md)
- [Error handling](./errors.md)
- [API reference](./api.md)
```

---

## What NOT to Document

- Obvious getters and setters (`getId()`, `setName()`)
- Private implementation details that change frequently
- Comments that repeat the code (`i++ // increment i`)
- TODO comments in committed code — use issue tracker instead
